#!/usr/bin/env ruby
# frozen_string_literal: true

# e2e/observability_test.rb -- static-only end-to-end test for the cluster-wide
# observability epic (kube-prometheus-stack + ApplicationSet generator
# consistency).
#
# WHY STATIC-ONLY
# ---------------
# This is a pure GitOps manifest repo: Argo CD ApplicationSets and plain
# Kubernetes YAML, no application code. There is no cluster in CI and there
# never will be one on the critical path, so "end to end" here means: assert
# that the committed manifests describe a coherent, deployable system, end to
# end, including the cross-file contracts that otherwise only break at runtime.
#
# The high-value assertions are the CROSS-FILE ones in section 6. Any single
# file can be individually valid while the fleet is still broken -- the Grafana
# HTTPRoute targeting a Service name the chart's releaseName no longer
# produces, or attaching to a Gateway the traefik chart doesn't create. Those
# are the failures that cost an afternoon of `kubectl describe`, and every one
# of them is statically decidable from the manifests. This test decides them.
#
# WHY RUBY AND NOT BASH
# ---------------------
# Two constraints, one answer. `pvg verify --check-e2e` only scans recognized
# source extensions -- a `.sh` file is invisible to it regardless of path or
# name, so a shell script cannot satisfy the epic gate. And this repo has no
# test tooling at all, so a test that needs `yq`/`jq`/PyYAML installed is a
# test that silently stops running. Ruby is scanned by the gate AND carries
# YAML in its stdlib, so this file has zero external dependencies and runs
# as-is on a stock macOS workstation and a stock CI runner alike.
#
# USAGE
#   ./e2e/observability_test.rb        # run from anywhere; exits 1 on failure

require 'yaml'
require 'json'

REPO_ROOT = File.expand_path('..', __dir__)

# ---------------------------------------------------------------------------
# Harness
# ---------------------------------------------------------------------------
# Accumulate-and-report rather than fail-fast: one run surfaces the whole blast
# radius, so a CI log shows every broken contract instead of just the first.
#
# Both streams are unbuffered on purpose. Ruby line-buffers $stdout only when it
# is a TTY, while $stderr is always unbuffered -- so when CI redirects both to
# one file, a buffered PASS line and an unbuffered FAIL line interleave and glue
# together ("PASS: ...grafanaFAIL: httproute..."), losing the failure to any
# line-oriented log scraper. Syncing both keeps the transcript ordered.
$stdout.sync = true
$stderr.sync = true

PASSES = []
FAILURES = []

def pass(desc)
  PASSES << desc
  puts "PASS: #{desc}"
end

def fail_assert(desc)
  FAILURES << desc
  warn "FAIL: #{desc}"
end

def section(title)
  puts
  puts "== #{title}"
end

def assert_eq(desc, expected, actual)
  if expected == actual
    pass(desc)
  else
    fail_assert("#{desc} -- expected #{expected.inspect}, got #{actual.inspect}")
  end
end

def assert_true(desc, actual)
  assert_eq(desc, true, actual)
end

def assert_file(desc, path)
  if File.file?(path)
    pass(desc)
  else
    fail_assert("#{desc} -- file not found: #{rel(path)}")
  end
end

def assert_match_absent(desc, regex, path)
  return fail_assert("#{desc} -- file not found: #{rel(path)}") unless File.file?(path)

  hit = raw(path).each_line.find { |l| l =~ regex }
  if hit
    fail_assert("#{desc} -- forbidden pattern #{regex.inspect} found in #{rel(path)}: #{hit.strip.inspect}")
  else
    pass(desc)
  end
end

def assert_match_present(desc, regex, path)
  return fail_assert("#{desc} -- file not found: #{rel(path)}") unless File.file?(path)

  if raw(path) =~ regex
    pass(desc)
  else
    fail_assert("#{desc} -- expected pattern #{regex.inspect} not found in #{rel(path)}")
  end
end

def rel(path)
  path.sub("#{REPO_ROOT}/", '')
end

# ---------------------------------------------------------------------------
# Loading
# ---------------------------------------------------------------------------

def raw(path)
  @raw ||= {}
  @raw[path] ||= File.read(path)
end

def doc(path)
  @docs ||= {}
  return @docs[path] if @docs.key?(path)

  @docs[path] =
    if File.file?(path)
      # Psych 4 (Ruby 3.1+) made YAML.load_file safe-by-default; unsafe_load_file
      # keeps behavior identical across the 2.6 shipped on macOS and modern CI.
      if YAML.respond_to?(:unsafe_load_file)
        YAML.unsafe_load_file(path)
      else
        YAML.load_file(path)
      end
    end
rescue StandardError => e
  fail_assert("could not parse #{rel(path)}: #{e.message}")
  @docs[path] = nil
end

# dig_path(obj, 'spec.template.spec.destination.name') -- numeric segments index
# into arrays, so 'spec.sources.0.chart' works too.
def dig_path(obj, path)
  path.split('.').reduce(obj) do |acc, key|
    break nil if acc.nil?

    if key =~ /\A\d+\z/
      acc.is_a?(Array) ? acc[key.to_i] : nil
    else
      acc.is_a?(Hash) ? acc[key] : nil
    end
  end
end

# assert_yaml <desc>, <file>, <dotted-path>, <expected>
def assert_yaml(desc, path, dotted, expected)
  assert_eq(desc, expected, dig_path(doc(path), dotted))
end

# ---------------------------------------------------------------------------

SELECTOR_KEY = 'akuity.io/argo-cd-cluster-name'

KPS_APPSET     = File.join(REPO_ROOT, 'infrastructure/kube-prometheus-stack/argocd/appset.yaml')
TRAEFIK_APPSET = File.join(REPO_ROOT, 'infrastructure/traefik-gateway/argocd/appset.yaml')
SECRETS_DIR    = File.join(REPO_ROOT, 'infrastructure/kube-prometheus-stack/secrets')
HTTPROUTE      = File.join(SECRETS_DIR, 'grafana-httproute.yaml')
SEALED_SECRET  = File.join(SECRETS_DIR, 'secret-grafana-admin.sealed.yaml')
INFRA_DOCS     = File.join(REPO_ROOT, 'docs/infra-dependencies.md')
BOOTSTRAP      = File.join(REPO_ROOT, 'bootstrap/infra-apps.yaml')

puts 'argo-fleet observability e2e (static)'
puts "repo:  #{REPO_ROOT}"
puts "ruby:  #{RUBY_VERSION}"

# ---------------------------------------------------------------------------
section '1. ApplicationSet generator consistency (every infrastructure appset)'
# ---------------------------------------------------------------------------
# Globbed rather than hard-coded against the five migrated appsets, so a NEW
# infra dependency added later with the old `list` shape fails here too. The
# expected-set check keeps the glob honest -- a silently deleted appset would
# otherwise reduce this whole section to vacuous success.

EXPECTED_INFRA_APPS = %w[
  argo-rollouts-crds
  gateway-api-crds
  kube-prometheus-stack
  openebs-localpv
  sealed-secrets
  traefik-gateway
].freeze

EXPECTED_INFRA_APPS.each do |app|
  assert_file("infrastructure/#{app} has an appset",
              File.join(REPO_ROOT, "infrastructure/#{app}/argocd/appset.yaml"))
end

appsets = Dir.glob(File.join(REPO_ROOT, 'infrastructure/*/argocd/appset.yaml')).sort
assert_eq('every expected infrastructure appset is discovered by the glob',
          EXPECTED_INFRA_APPS,
          appsets.map { |p| p.split('/')[-3] }.sort)

appsets.each do |appset|
  r = rel(appset)
  d = doc(appset)
  name = dig_path(d, 'metadata.name')

  assert_yaml("#{r}: is an ApplicationSet", appset, 'kind', 'ApplicationSet')

  # Exactly one generator, and it is `clusters` -- not the old `list`.
  assert_eq("#{r}: declares exactly one generator", 1,
            (dig_path(d, 'spec.generators') || []).length)
  assert_true("#{r}: uses a clusters generator",
              (dig_path(d, 'spec.generators.0') || {}).key?('clusters'))
  assert_eq("#{r}: no legacy list generator", false,
            (dig_path(d, 'spec.generators.0') || {}).key?('list'))

  # The selector is what keeps infra off the control plane. Checked
  # semantically (NotIn + contains both) rather than by exact array equality,
  # so excluding an additional cluster later is not a spurious failure.
  expr = dig_path(d, 'spec.generators.0.clusters.selector.matchExpressions.0') || {}
  assert_eq("#{r}: selector keys on #{SELECTOR_KEY}", SELECTOR_KEY, expr['key'])
  assert_eq("#{r}: selector operator is NotIn", 'NotIn', expr['operator'])
  assert_true("#{r}: selector excludes in-cluster",
              (expr['values'] || []).include?('in-cluster'))
  assert_true("#{r}: selector excludes kargo",
              (expr['values'] || []).include?('kargo'))

  # destination.name / {{name}}, never destination.server: on an Akuity-hosted
  # instance {{server}} resolves to an unreachable internal proxy URL.
  assert_yaml("#{r}: destination.name templates {{name}}",
              appset, 'spec.template.spec.destination.name', '{{name}}')
  assert_eq("#{r}: destination.server is never set", false,
            (dig_path(d, 'spec.template.spec.destination') || {}).key?('server'))
  assert_yaml("#{r}: Application name templates {{name}}",
              appset, 'spec.template.metadata.name', "#{name}-{{name}}")

  # Belt-and-braces sweep for a {{server}} reference ANYWHERE in the rendered
  # Application, including inside a Helm value where the structural
  # destination.server check above would not look. Searches the PARSED document
  # rather than the file text specifically so that the explanatory comments
  # warning against {{server}} do not trip it.
  if d.to_json =~ /\{\{ *server *\}\}/
    fail_assert("#{r}: references {{server}} (an unreachable internal proxy URL on an Akuity-hosted instance)")
  else
    pass("#{r}: no {{server}} reference in the rendered Application")
  end
end

# ---------------------------------------------------------------------------
section '2. kube-prometheus-stack Application'
# ---------------------------------------------------------------------------

assert_yaml('kps: sources[0] is the kube-prometheus-stack chart',
            KPS_APPSET, 'spec.template.spec.sources.0.chart', 'kube-prometheus-stack')
assert_yaml('kps: chart pulled from prometheus-community',
            KPS_APPSET, 'spec.template.spec.sources.0.repoURL',
            'https://prometheus-community.github.io/helm-charts')
assert_true('kps: chart version is pinned (not HEAD/latest)',
            dig_path(doc(KPS_APPSET), 'spec.template.spec.sources.0.targetRevision').to_s =~ /\A\d+\.\d+\.\d+\z/ ? true : false)

# AGENTS.md non-negotiable: Argo CD renders with `helm template` and no cluster
# access, so the grafana subchart's `lookup`-based password generation misses on
# EVERY sync and would rotate the admin password each time. existingSecret is
# the only correct answer, and its absence is silent -- hence asserted here.
assert_yaml('kps: grafana.admin.existingSecret is set (no lookup-regenerated password)',
            KPS_APPSET,
            'spec.template.spec.sources.0.helm.valuesObject.grafana.admin.existingSecret',
            'grafana-admin')
assert_yaml('kps: grafana admin userKey set',
            KPS_APPSET,
            'spec.template.spec.sources.0.helm.valuesObject.grafana.admin.userKey',
            'admin-user')
assert_yaml('kps: grafana admin passwordKey set',
            KPS_APPSET,
            'spec.template.spec.sources.0.helm.valuesObject.grafana.admin.passwordKey',
            'admin-password')
assert_match_absent('kps: no plaintext grafana password in the appset',
                    /^\s*(adminPassword|password):\s*[^\s#]/, KPS_APPSET)

# storageClassName pinned explicitly: relying on the default StorageClass is
# exactly the silent never-binds-forever incident this fleet already had once.
assert_yaml('kps: prometheus PVC pins storageClassName=local-path',
            KPS_APPSET,
            'spec.template.spec.sources.0.helm.valuesObject.prometheus.prometheusSpec.' \
            'storageSpec.volumeClaimTemplate.spec.storageClassName',
            'local-path')

# Six prometheus-operator CRDs exceed the client-side-apply annotation limit.
sync_options = dig_path(doc(KPS_APPSET), 'spec.template.spec.syncPolicy.syncOptions') || []
assert_true('kps: syncOptions includes ServerSideApply=true',
            sync_options.include?('ServerSideApply=true'))
assert_true('kps: syncOptions includes CreateNamespace=true',
            sync_options.include?('CreateNamespace=true'))

# Second source: the git directory carrying the SealedSecret AND the HTTPRoute.
# Widening the glob from '*.sealed.yaml' to '*.yaml' is load-bearing -- the
# narrower glob drops the HTTPRoute silently, leaving it correct in git and
# absent from every cluster.
assert_yaml('kps: sources[1] points at the secrets directory',
            KPS_APPSET, 'spec.template.spec.sources.1.path',
            'infrastructure/kube-prometheus-stack/secrets')
assert_yaml("kps: sources[1] directory glob is '*.yaml' (widened from '*.sealed.yaml')",
            KPS_APPSET, 'spec.template.spec.sources.1.directory.include', '*.yaml')

# Every file actually sitting in secrets/ must be matched by that glob --
# otherwise a future *.json or *.yml lands in git and never reaches a cluster.
glob = dig_path(doc(KPS_APPSET), 'spec.template.spec.sources.1.directory.include').to_s
unmatched = Dir.glob(File.join(SECRETS_DIR, '*')).select do |f|
  File.file?(f) && !File.fnmatch(glob, File.basename(f))
end
if unmatched.empty?
  pass('kps: every file in secrets/ is matched by the directory glob')
else
  fail_assert("kps: files in secrets/ not matched by #{glob.inspect}: " \
              "#{unmatched.map { |f| File.basename(f) }.join(', ')}")
end

# ---------------------------------------------------------------------------
section '3. kube-prometheus-stack ignoreDifferences (Gateway API defaults)'
# ---------------------------------------------------------------------------
# The API server defaults six fields on every HTTPRoute at admission, so the
# live object is permanently a superset of git and the Application reports
# OutOfSync forever. The fix must stay SCOPED: a blanket ignore of `spec` would
# also hide a real change to a backendRef port or a parentRef name.

ignore_diffs = dig_path(doc(KPS_APPSET), 'spec.template.spec.ignoreDifferences') || []
assert_true('kps: ignoreDifferences is present', !ignore_diffs.empty?)

entry = ignore_diffs.find { |e| e['kind'] == 'HTTPRoute' && e['name'] == 'grafana' } || {}
assert_eq('kps: ignoreDifferences scoped to gateway.networking.k8s.io',
          'gateway.networking.k8s.io', entry['group'])
assert_eq('kps: ignoreDifferences scoped to kind HTTPRoute', 'HTTPRoute', entry['kind'])
assert_eq('kps: ignoreDifferences scoped to name grafana', 'grafana', entry['name'])
assert_eq('kps: ignoreDifferences scoped to namespace monitoring', 'monitoring', entry['namespace'])

exprs = entry['jqPathExpressions'] || []
assert_true('kps: ignoreDifferences names specific fields via jqPathExpressions',
            !exprs.empty?)

# Named leaves, not a wildcard.
blanket = exprs.select { |e| ['.spec', '.spec[]', '.spec.*', '.'].include?(e) }
assert_eq('kps: ignoreDifferences is NOT a blanket ignore of spec', [], blanket)
assert_eq('kps: every ignored path is a leaf under .spec.',
          [], exprs.reject { |e| e.start_with?('.spec.') })
assert_eq('kps: no blanket jsonPointer ignore of /spec',
          [], (entry['jsonPointers'] || []).select { |p| ['/spec', ''].include?(p) })

# The fields a real regression would touch must NOT be ignored.
assert_eq('kps: backendRef name/port are still diffed (not ignored)',
          [], exprs.select { |e| e.end_with?('.name') || e.end_with?('.port') })

# ---------------------------------------------------------------------------
section '4. Grafana HTTPRoute'
# ---------------------------------------------------------------------------

assert_file('grafana-httproute.yaml exists', HTTPROUTE)
assert_yaml('httproute: kind is HTTPRoute', HTTPROUTE, 'kind', 'HTTPRoute')
assert_yaml('httproute: uses the v1 Gateway API group',
            HTTPROUTE, 'apiVersion', 'gateway.networking.k8s.io/v1')
assert_yaml('httproute: named grafana', HTTPROUTE, 'metadata.name', 'grafana')
assert_yaml('httproute: lives in the monitoring namespace',
            HTTPROUTE, 'metadata.namespace', 'monitoring')
assert_yaml('httproute: parentRefs[0].name is traefik-gateway',
            HTTPROUTE, 'spec.parentRefs.0.name', 'traefik-gateway')
assert_yaml('httproute: parentRefs[0].namespace is traefik',
            HTTPROUTE, 'spec.parentRefs.0.namespace', 'traefik')
assert_yaml('httproute: backendRefs[0].name is kube-prometheus-stack-grafana',
            HTTPROUTE, 'spec.rules.0.backendRefs.0.name', 'kube-prometheus-stack-grafana')
assert_yaml('httproute: backendRefs[0].port is 80',
            HTTPROUTE, 'spec.rules.0.backendRefs.0.port', 80)

# ---------------------------------------------------------------------------
section '5. Traefik Gateway cross-namespace route admission'
# ---------------------------------------------------------------------------
# Gateway API defaults allowedRoutes.namespaces.from to `Same`. Without `All`
# the Gateway accepts routes from the `traefik` namespace only, so the Grafana
# route (in `monitoring`) attaches to nothing -- no error at apply time, just a
# 404 at request time.

TRAEFIK_VALUES = 'spec.template.spec.source.helm.valuesObject'
assert_yaml('traefik: gateway is enabled',
            TRAEFIK_APPSET, "#{TRAEFIK_VALUES}.gateway.enabled", true)
assert_yaml('traefik: gateway is named traefik-gateway',
            TRAEFIK_APPSET, "#{TRAEFIK_VALUES}.gateway.name", 'traefik-gateway')
assert_yaml('traefik: web listener admits routes from All namespaces',
            TRAEFIK_APPSET,
            "#{TRAEFIK_VALUES}.gateway.listeners.web.namespacePolicy.from", 'All')
assert_yaml('traefik: kubernetesGateway provider enabled',
            TRAEFIK_APPSET,
            "#{TRAEFIK_VALUES}.providers.kubernetesGateway.enabled", true)

# ---------------------------------------------------------------------------
section '6. Cross-file contracts (the failures that only bite at runtime)'
# ---------------------------------------------------------------------------

# The HTTPRoute hard-codes a Service name the chart derives from
# helm.releaseName. Drift between the two yields a route to nowhere.
release = dig_path(doc(KPS_APPSET), 'spec.template.spec.sources.0.helm.releaseName')
assert_eq('kps: helm.releaseName is pinned to kube-prometheus-stack',
          'kube-prometheus-stack', release)
assert_eq('cross: HTTPRoute backend matches <releaseName>-grafana',
          "#{release}-grafana",
          dig_path(doc(HTTPROUTE), 'spec.rules.0.backendRefs.0.name'))

# The route's parent must be the Gateway the traefik chart actually creates...
assert_eq("cross: HTTPRoute parentRef matches the traefik chart's gateway.name",
          dig_path(doc(TRAEFIK_APPSET), "#{TRAEFIK_VALUES}.gateway.name"),
          dig_path(doc(HTTPROUTE), 'spec.parentRefs.0.name'))

# ...in the namespace traefik is actually deployed to.
assert_eq("cross: HTTPRoute parentRef namespace matches traefik's destination namespace",
          dig_path(doc(TRAEFIK_APPSET), 'spec.template.spec.destination.namespace'),
          dig_path(doc(HTTPROUTE), 'spec.parentRefs.0.namespace'))

# The route and the Grafana workload must land in the same namespace.
assert_eq('cross: HTTPRoute namespace matches the kube-prometheus-stack destination namespace',
          dig_path(doc(KPS_APPSET), 'spec.template.spec.destination.namespace'),
          dig_path(doc(HTTPROUTE), 'metadata.namespace'))

# ignoreDifferences must target the route that actually exists.
assert_eq('cross: ignoreDifferences name matches the real HTTPRoute name',
          dig_path(doc(HTTPROUTE), 'metadata.name'), entry['name'])
assert_eq('cross: ignoreDifferences namespace matches the real HTTPRoute namespace',
          dig_path(doc(HTTPROUTE), 'metadata.namespace'), entry['namespace'])

# grafana.admin.existingSecret must name the SealedSecret that is committed.
assert_eq('cross: grafana existingSecret matches the committed SealedSecret name',
          dig_path(doc(SEALED_SECRET), 'metadata.name'),
          dig_path(doc(KPS_APPSET),
                   'spec.template.spec.sources.0.helm.valuesObject.grafana.admin.existingSecret'))
assert_eq('cross: SealedSecret namespace matches the Grafana destination namespace',
          dig_path(doc(KPS_APPSET), 'spec.template.spec.destination.namespace'),
          dig_path(doc(SEALED_SECRET), 'metadata.namespace'))

# The keys the chart reads must be the keys the SealedSecret actually provides.
encrypted = dig_path(doc(SEALED_SECRET), 'spec.encryptedData') || {}
{ 'userKey' => 'admin-user', 'passwordKey' => 'admin-password' }.each do |field, _|
  referenced = dig_path(
    doc(KPS_APPSET),
    "spec.template.spec.sources.0.helm.valuesObject.grafana.admin.#{field}"
  )
  assert_true("cross: SealedSecret provides the key referenced by grafana.admin.#{field} " \
              "(#{referenced.inspect})",
              encrypted.key?(referenced))
end

# ---------------------------------------------------------------------------
section '7. SealedSecret contains no plaintext'
# ---------------------------------------------------------------------------

assert_file('grafana admin SealedSecret exists', SEALED_SECRET)
assert_yaml('sealed: kind is SealedSecret', SEALED_SECRET, 'kind', 'SealedSecret')
assert_yaml('sealed: apiVersion is bitnami.com/v1alpha1',
            SEALED_SECRET, 'apiVersion', 'bitnami.com/v1alpha1')
assert_match_present('sealed: carries encryptedData', /^\s*encryptedData:/, SEALED_SECRET)

# Anchored so `encryptedData:` does not trip these. A `data:`/`stringData:`
# block in a SealedSecret means someone committed a plain Secret by mistake.
assert_match_absent('sealed: no stringData block', /^\s*stringData:/, SEALED_SECRET)
assert_match_absent('sealed: no plain data block', /^\s*data:/, SEALED_SECRET)
assert_match_absent('sealed: not a plain core/v1 Secret', /^kind:\s*Secret\s*$/, SEALED_SECRET)

# Sealed values are RSA+AES ciphertext: long and base64. A short or non-base64
# value means something unencrypted got pasted in.
%w[admin-password admin-user].each do |key|
  value = encrypted[key].to_s
  assert_true("sealed: #{key} ciphertext is long enough to be encrypted (#{value.length} chars)",
              value.length > 100)
  assert_true("sealed: #{key} ciphertext is base64",
              !(value =~ %r{\A[A-Za-z0-9+/=]+\z}).nil?)
end

# ---------------------------------------------------------------------------
section '8. Documentation reflects the clusters-generator convention'
# ---------------------------------------------------------------------------

assert_file('docs/infra-dependencies.md exists', INFRA_DOCS)
assert_match_absent("docs: no longer instructs 'Use a `list`'", /Use a `list`/, INFRA_DOCS)
assert_match_absent('docs: no legacy list-generator example', /^\s*-\s*list:/, INFRA_DOCS)
assert_match_present('docs: documents the clusters generator', /Use a `clusters`/, INFRA_DOCS)
assert_match_present('docs: documents the cluster-name selector key',
                     /#{Regexp.escape(SELECTOR_KEY)}/, INFRA_DOCS)

# ---------------------------------------------------------------------------
section '9. Bootstrap discovery untouched by this epic'
# ---------------------------------------------------------------------------
# Cheap regression guard: nothing in an observability change should have reached
# into bootstrap/. The infra app-of-apps must still be a git generator
# discovering infrastructure/*/argocd and syncing to the control plane.

assert_file('bootstrap/infra-apps.yaml exists', BOOTSTRAP)
assert_yaml('bootstrap: infra-apps is an ApplicationSet', BOOTSTRAP, 'kind', 'ApplicationSet')
assert_true('bootstrap: still uses a git generator',
            (dig_path(doc(BOOTSTRAP), 'spec.generators.0') || {}).key?('git'))
assert_yaml('bootstrap: discovers infrastructure/*/argocd',
            BOOTSTRAP, 'spec.generators.0.git.directories.0.path', 'infrastructure/*/argocd')
assert_yaml('bootstrap: targets the in-cluster control plane',
            BOOTSTRAP, 'spec.template.spec.destination.name', 'in-cluster')
assert_yaml('bootstrap: control-plane destination stays namespace-scoped to argocd',
            BOOTSTRAP, 'spec.template.spec.destination.namespace', 'argocd')
assert_yaml('bootstrap: recurses into the discovered directory',
            BOOTSTRAP, 'spec.template.spec.source.directory.recurse', true)

# The whole reason the SealedSecret and the HTTPRoute live outside argocd/: the
# in-cluster control plane is namespace-scoped to `argocd` and has no
# SealedSecret CRD at all. If cluster-bound objects ever land under argocd/,
# that wholesale sync breaks.
stray = Dir.glob(File.join(REPO_ROOT, 'infrastructure/*/argocd/*')).select do |f|
  File.file?(f) && raw(f) =~ /^kind:\s*(SealedSecret|HTTPRoute)\s*$/
end
if stray.empty?
  pass('bootstrap: no cluster-bound objects under any infrastructure/*/argocd glob')
else
  fail_assert('bootstrap: cluster-bound objects found under argocd/ glob: ' \
              "#{stray.map { |f| rel(f) }.join(', ')}")
end

# ---------------------------------------------------------------------------
puts
puts '-' * 71
if FAILURES.empty?
  puts "RESULT: PASS -- #{PASSES.length} assertions, 0 failures"
  exit 0
end

warn "RESULT: FAIL -- #{PASSES.length} passed, #{FAILURES.length} failed"
warn ''
warn 'Failed assertions:'
FAILURES.each { |f| warn "  - #{f}" }
exit 1
