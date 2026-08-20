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

# ===========================================================================
# arr-stack: static verification capstone for apps/arr-stack/ (sections 10-15)
# ===========================================================================
# The `arr-stack` epic builds one shared template per half of the design --
# appset-workloads.yaml (18 workload Applications) and appset-kargo.yaml (6
# Kargo pipelines rendered from one vendored chart) -- so every per-app fact
# lives in exactly one place and is consumed somewhere else entirely. That is
# the whole point of the DRY generator pattern, and it is also its whole risk:
# NOTHING errors when the two halves disagree. A seventh app added to one list
# and not the other, a port that drifts from the design's parameter table, a
# digest bound into the wrong app-template field, a repoURL that swallows the
# chart name -- each is a perfectly valid YAML file and a broken fleet.
#
# This section decides all of those statically, and is deliberately paranoid
# about the three regressions this epic already suffered once each in real
# bug-triage rounds. Each one's full root cause is documented at the manifest it
# bit; the guards below are named for it:
#
#   1. tag-vs-digest, and its param path. `imageTag` holds a sha256 DIGEST, so
#      it binds to app-template's `digest:` field (which joins with "@"), never
#      `tag:` (which joins with ":" and yields an unparseable reference), via the
#      TOP-LEVEL `.imageTag` parameter, never `.values.imageTag` (an empty map,
#      which aborts all 18 renders under missingkey=error). All three wrong
#      shapes -- either param path bound to `tag:`, and `digest:` bound to the
#      nested path -- are guarded separately below.
#   2. overseerr -> seerr. hotio retired `ghcr.io/hotio/overseerr`, so a
#      Digest-strategy Warehouse against it never mints Freight. Any surviving
#      `overseerr` reference under apps/arr-stack/ IS the regression.
#   3. OCI source shape. An Argo CD Application's Helm source needs a repoURL
#      WITHOUT the `oci://` scheme plus an explicit non-empty `chart:`. Folding
#      the chart name into an `oci://` repoURL parses fine and then fails spec
#      validation at the API server (it did, on all 18, live).
#
# Every expected set below is DISCOVERED (glob, parse, or `helm template`
# render) rather than hard-coded, with one deliberate exception: ARR_APP_TABLE
# transcribes the epic's own per-app parameter table. That table is the design's
# source of truth and has to be an INDEPENDENT fourth opinion -- deriving it from
# the manifests it exists to police would make the whole cross-check vacuous.

require 'open3'
require 'tmpdir'

ARR_DIR        = File.join(REPO_ROOT, 'apps/arr-stack')
ARR_ARGOCD     = File.join(ARR_DIR, 'argocd')
ARR_APPPROJECT = File.join(ARR_ARGOCD, 'appproject.yaml')
ARR_WORKLOADS  = File.join(ARR_ARGOCD, 'appset-workloads.yaml')
ARR_KARGO      = File.join(ARR_ARGOCD, 'appset-kargo.yaml')
ARR_CHART_DIR  = File.join(ARR_ARGOCD, 'kargo-chart')
ARR_ENV_DIR    = File.join(ARR_DIR, 'env')

ARR_STAGES = %w[dev prod staging].freeze # sorted, not pipeline order
ARR_STAGE_ORDER = %w[dev staging prod].freeze

# The epic's per-app parameter table, transcribed. See the note above on why
# this one set is hard-coded rather than discovered.
ARR_APP_TABLE = {
  'sonarr'   => { 'image' => 'ghcr.io/hotio/sonarr',   'port' => '8989', 'hasDownloads' => 'true' },
  'radarr'   => { 'image' => 'ghcr.io/hotio/radarr',   'port' => '7878', 'hasDownloads' => 'true' },
  'lidarr'   => { 'image' => 'ghcr.io/hotio/lidarr',   'port' => '8686', 'hasDownloads' => 'true' },
  'bazarr'   => { 'image' => 'ghcr.io/hotio/bazarr',   'port' => '6767', 'hasDownloads' => 'true' },
  'prowlarr' => { 'image' => 'ghcr.io/hotio/prowlarr', 'port' => '9696', 'hasDownloads' => 'false' },
  'seerr'    => { 'image' => 'ghcr.io/hotio/seerr',    'port' => '5055', 'hasDownloads' => 'false' }
}.freeze

ARR_APPS = ARR_APP_TABLE.keys.sort.freeze

DIGEST_RE = /\Asha256:[0-9a-f]{64}\z/.freeze

# A real, resolvable digest for the render checks -- taken from the committed
# seed rather than invented, so the render exercises the same value shape the
# promotion pipeline actually writes.
ARR_SAMPLE_DIGEST = 'sha256:e029ce1988241f9d213ebafbc73012c4684d3c698523f18b597bb014b88d551a'

# ---------------------------------------------------------------------------
# arr-stack helpers
# ---------------------------------------------------------------------------

def arr_files
  @arr_files ||= Dir.glob(File.join(ARR_DIR, '**/*')).select { |f| File.file?(f) }.sort
end

# kargo-chart/templates/*.yaml are HELM TEMPLATES, not manifests: raw text like
# `name: {{ .Values.appName }}` is not valid standalone YAML (that is exactly
# why every file in the chart carries `+argocd:skip-file-rendering`). They are
# linted post-render in section 11 instead of parsed raw here.
def arr_chart_template?(path)
  path.start_with?(File.join(ARR_CHART_DIR, 'templates'))
end

def docs(path)
  @streams ||= {}
  return @streams[path] if @streams.key?(path)

  @streams[path] =
    if YAML.respond_to?(:load_stream)
      # Psych 4 made load_stream safe-by-default; the arr-stack manifests carry
      # no aliases or ruby tags, so the safe loader is sufficient on every Ruby.
      YAML.load_stream(File.read(path)).compact
    end
rescue StandardError => e
  fail_assert("could not parse #{rel(path)} as a YAML stream: #{e.message}")
  @streams[path] = nil
end

def which(bin)
  ENV.fetch('PATH', '').split(File::PATH_SEPARATOR).each do |dir|
    candidate = File.join(dir, bin)
    return candidate if File.file?(candidate) && File.executable?(candidate)
  end
  nil
end

def git_out(*args)
  out, _err, status = Open3.capture3('git', '-C', REPO_ROOT, *args)
  status.success? ? out : nil
rescue StandardError
  nil
end

def assert_absent_in_tree(desc, regex, files)
  hits = files.select { |f| raw(f) =~ regex }
  if hits.empty?
    pass(desc)
  else
    fail_assert("#{desc} -- forbidden pattern #{regex.inspect} found in: " \
                "#{hits.map { |f| rel(f) }.join(', ')}")
  end
end

# Evaluates the ONE Go-template construct appset-workloads.yaml's `helm.values`
# block scalar actually uses: a `{{- if eq .field "literal"}}`/`{{- end}}` pair
# plus `{{.field}}` leaf substitution. Deliberately NOT a general template
# engine -- an unrecognised action survives into the output and is caught by the
# "no unsubstituted action" assertion, rather than being silently swallowed.
def arr_render_values(raw_values, params)
  skipping = false
  kept = []
  raw_values.each_line do |line|
    if line =~ /\{\{-?\s*if\s+eq\s+\.(\w+)\s+"([^"]*)"\s*-?\}\}/
      skipping = params[Regexp.last_match(1)].to_s != Regexp.last_match(2)
      next
    end
    if line =~ /\{\{-?\s*end\s*-?\}\}/
      skipping = false
      next
    end
    next if skipping

    kept << line
  end
  kept.join.gsub(/\{\{\s*\.(\w+)\s*\}\}/) { params.fetch(Regexp.last_match(1), Regexp.last_match(0)) }
end

# Reads the `helm.values` block scalar as YAML WITHOUT substituting anything, by
# dropping the Go-template control lines and quoting the bare leaf actions. This
# is how the BINDING itself is inspected structurally (which app-template field
# is wired to which generator parameter) rather than by grepping text.
def arr_values_as_yaml(raw_values)
  text = raw_values.to_s.each_line.reject { |l| l =~ /\{\{-?\s*(if|else|end)\b/ }.join
  # `repository: {{.image}}` -> `repository: '{{.image}}'`. Actions that are
  # already quoted (`digest: "{{.imageTag}}"`) do not match and are left alone.
  YAML.load(text.gsub(/:[ \t]*(\{\{[^}]*\}\})[ \t]*$/) { ": '#{Regexp.last_match(1)}'" })
rescue StandardError => e
  fail_assert("arr: could not read appset-workloads.yaml's helm.values as YAML: #{e.message}")
  nil
end

# metadata.annotations keys contain dots (`argocd.argoproj.io/sync-wave`), which
# dig_path would split into path segments. Fetch the map, then index it.
def arr_annotation(obj, dotted_parent, key)
  (dig_path(obj, dotted_parent) || {})[key]
end

# app-template's own rule, from charts/common/templates/lib/common/
# _imageSpecificationToImage.tpl: repository + "@" + digest when a digest is
# given, repository + ":" + tag otherwise. Re-derived here so the digest-vs-tag
# OUTCOME is asserted even when the upstream OCI registry is unreachable.
def arr_image_ref(image_block)
  return nil unless image_block.is_a?(Hash)

  if image_block['digest'].to_s != ''
    "#{image_block['repository']}@#{image_block['digest']}"
  else
    "#{image_block['repository']}:#{image_block['tag']}"
  end
end

ARR_HELM = which('helm')

# ---------------------------------------------------------------------------
section '10. arr-stack structural / lint checks'
# ---------------------------------------------------------------------------
# Accumulate-and-report like every other section: a broken release.yaml must not
# hide a broken ApplicationSet.

%w[appproject.yaml appset-workloads.yaml appset-kargo.yaml].each do |f|
  assert_file("arr: apps/arr-stack/argocd/#{f} exists", File.join(ARR_ARGOCD, f))
end
assert_file('arr: kargo-chart/Chart.yaml exists', File.join(ARR_CHART_DIR, 'Chart.yaml'))

# 3 argocd manifests + Chart.yaml + 4 chart templates + 18 release.yaml = 26.
# Asserted as a derived total so a stray file (or a deleted one) is loud.
assert_eq('arr: apps/arr-stack/ holds exactly the expected file count (3+1+4+18)',
          26, arr_files.length)
assert_eq('arr: every file under apps/arr-stack/ is YAML',
          [], arr_files.reject { |f| f.end_with?('.yaml') }.map { |f| rel(f) })

arr_files.each do |f|
  r = rel(f)
  body = raw(f)

  # Universal yamllint rules, applied to Helm templates and plain manifests
  # alike because they are text-level and templating-agnostic.
  assert_eq("lint #{r}: no tab characters", false, body.include?("\t"))
  assert_eq("lint #{r}: no trailing whitespace on any line", [],
            body.each_line.each_with_index.select { |l, _| l.chomp =~ /[ \t]+\z/ }
                .map { |_, i| i + 1 })
  assert_true("lint #{r}: ends with a newline", body.end_with?("\n"))

  next if arr_chart_template?(f)

  stream = docs(f)
  assert_true("lint #{r}: parses cleanly as a YAML stream", !stream.nil?)
  next if stream.nil?

  assert_true("lint #{r}: is a non-empty YAML stream", !stream.empty?)
  assert_eq("lint #{r}: every document is a mapping", [],
            stream.reject { |d| d.is_a?(Hash) }.map(&:class).map(&:to_s))
end

# The three argocd/ manifests are real Kubernetes objects and must say so.
{ ARR_APPPROJECT => %w[AppProject arr-stack],
  ARR_WORKLOADS => %w[ApplicationSet arr-stack-workloads],
  ARR_KARGO => %w[ApplicationSet arr-stack-kargo] }.each do |path, (kind, name)|
  assert_yaml("arr: #{rel(path)} apiVersion is argoproj.io/v1alpha1", path, 'apiVersion',
              'argoproj.io/v1alpha1')
  assert_yaml("arr: #{rel(path)} kind is #{kind}", path, 'kind', kind)
  assert_yaml("arr: #{rel(path)} is named #{name}", path, 'metadata.name', name)
  assert_yaml("arr: #{rel(path)} lives in the argocd namespace", path, 'metadata.namespace',
              'argocd')
end

# release.yaml files are promotion-target VALUES files, not manifests: exactly
# two keys, nothing else. An apiVersion/kind here would mean someone confused
# the contract.
Dir.glob(File.join(ARR_ENV_DIR, '*/*/release.yaml')).sort.each do |f|
  assert_eq("lint #{rel(f)}: declares exactly the imageTag/values contract keys",
            %w[imageTag values], (doc(f) || {}).keys.sort)
end

# ---------------------------------------------------------------------------
section '11. arr-stack helm template renders'
# ---------------------------------------------------------------------------

if ARR_HELM.nil?
  fail_assert('arr/render: `helm` is not on PATH -- the render checks below could not run, ' \
              'and an unexecuted check is not a passing check')
else
  pass("arr/render: helm found at #{ARR_HELM}")
end

# --- 11a. the vendored Kargo chart, rendered per app ------------------------
# One hasDownloads:true app and one :false app, matching the chart's own
# original verification. The chart itself is hasDownloads-agnostic; rendering
# both keeps this check honest if that ever changes.
ARR_RENDERED_KARGO = {}

%w[sonarr prowlarr].each do |app|
  image = ARR_APP_TABLE.fetch(app)['image']
  next if ARR_HELM.nil?

  out, err, status = Open3.capture3(ARR_HELM, 'template', app, ARR_CHART_DIR,
                                    '--set', "appName=#{app}", '--set', "image=#{image}")
  unless status.success?
    fail_assert("arr/render: `helm template` of kargo-chart for #{app} failed: #{err.strip}")
    next
  end
  pass("arr/render: kargo-chart renders cleanly for #{app}")

  rendered = begin
    YAML.load_stream(out).compact
  rescue StandardError => e
    fail_assert("arr/render: rendered kargo-chart for #{app} is not parseable YAML: #{e.message}")
    nil
  end
  next if rendered.nil?

  ARR_RENDERED_KARGO[app] = rendered

  # Post-render lint: this is where stages.yaml's multi-document shape is
  # actually validated (it cannot be parsed raw -- see arr_chart_template?).
  assert_eq("arr/render #{app}: every rendered document is a mapping", [],
            rendered.reject { |d| d.is_a?(Hash) }.map(&:class).map(&:to_s))
  assert_eq("arr/render #{app}: every rendered document declares the kargo API group", [],
            rendered.map { |d| d['apiVersion'] }.uniq.reject { |v| v == 'kargo.akuity.io/v1alpha1' })

  # A well-formed, app-name-scoped Project/Warehouse/3xStage/PromotionTask set.
  assert_eq("arr/render #{app}: renders exactly the Project/Warehouse/3xStage/PromotionTask set",
            { 'Project' => 1, 'Warehouse' => 1, 'Stage' => 3, 'PromotionTask' => 1 },
            rendered.each_with_object({}) { |d, h| h[d['kind']] = (h[d['kind']] || 0) + 1 })

  project = rendered.find { |d| d['kind'] == 'Project' }
  assert_eq("arr/render #{app}: Project is named for the app", app,
            dig_path(project, 'metadata.name'))
  assert_eq("arr/render #{app}: Project carries sync-wave \"-1\"", '-1',
            arr_annotation(project, 'metadata.annotations', 'argocd.argoproj.io/sync-wave'))

  warehouse = rendered.find { |d| d['kind'] == 'Warehouse' }
  assert_eq("arr/render #{app}: Warehouse is app-name-scoped", [app, app],
            [dig_path(warehouse, 'metadata.name'), dig_path(warehouse, 'metadata.namespace')])
  subs = dig_path(warehouse, 'spec.subscriptions') || []
  assert_eq("arr/render #{app}: Warehouse declares exactly one subscription", 1, subs.length)
  assert_eq("arr/render #{app}: Warehouse subscribes to the app's image", image,
            dig_path(subs[0], 'image.repoURL'))
  assert_eq("arr/render #{app}: Warehouse uses imageSelectionStrategy Digest", 'Digest',
            dig_path(subs[0], 'image.imageSelectionStrategy'))
  assert_eq("arr/render #{app}: Warehouse watches the mutable `release` channel tag", 'release',
            dig_path(subs[0], 'image.constraint'))

  stages = rendered.select { |d| d['kind'] == 'Stage' }
  assert_eq("arr/render #{app}: Stages are exactly dev/staging/prod", ARR_STAGES,
            stages.map { |s| dig_path(s, 'metadata.name') }.sort)
  assert_eq("arr/render #{app}: every Stage is namespaced to the app", [app],
            stages.map { |s| dig_path(s, 'metadata.namespace') }.uniq)
  assert_eq("arr/render #{app}: every Stage requests Freight from the app's Warehouse", [app],
            stages.map { |s| dig_path(s, 'spec.requestedFreight.0.origin.name') }.uniq)
  assert_eq("arr/render #{app}: every Stage promotes via the shared `promote` task", ['promote'],
            stages.map { |s| dig_path(s, 'spec.promotionTemplate.spec.steps.0.task.name') }.uniq)

  # dev <- Warehouse direct; staging <- dev; prod <- staging.
  by_name = stages.each_with_object({}) { |s, h| h[dig_path(s, 'metadata.name')] = s }
  assert_eq("arr/render #{app}: dev sources Freight directly from the Warehouse", true,
            dig_path(by_name['dev'], 'spec.requestedFreight.0.sources.direct'))
  assert_eq("arr/render #{app}: staging sources Freight from dev", ['dev'],
            dig_path(by_name['staging'], 'spec.requestedFreight.0.sources.stages'))
  assert_eq("arr/render #{app}: prod sources Freight from staging", ['staging'],
            dig_path(by_name['prod'], 'spec.requestedFreight.0.sources.stages'))

  task = rendered.find { |d| d['kind'] == 'PromotionTask' }
  assert_eq("arr/render #{app}: PromotionTask is the app-scoped `promote` task", ['promote', app],
            [dig_path(task, 'metadata.name'), dig_path(task, 'metadata.namespace')])
  assert_eq("arr/render #{app}: PromotionTask binds the app's image as a var", image,
            (dig_path(task, 'spec.vars') || []).map { |v| v['value'] if v['name'] == 'image' }
                                              .compact.first)
end

# --- 11b. appset-workloads.yaml's helm.values, both hasDownloads branches ---
ARR_WORKLOAD_VALUES = dig_path(doc(ARR_WORKLOADS), 'spec.template.spec.source.helm.values')
assert_true('arr/render: appset-workloads.yaml carries a raw `helm.values` string ' \
            '(valuesObject cannot build the conditional persistence block)',
            ARR_WORKLOAD_VALUES.is_a?(String) && !ARR_WORKLOAD_VALUES.empty?)

ARR_RENDERED_WORKLOADS = {}

%w[sonarr prowlarr].each do |app|
  next unless ARR_WORKLOAD_VALUES.is_a?(String)

  spec = ARR_APP_TABLE.fetch(app)
  params = spec.merge('name' => app, 'imageTag' => ARR_SAMPLE_DIGEST)
  rendered = arr_render_values(ARR_WORKLOAD_VALUES, params)

  # A surviving `{{` means the values block references a parameter the
  # generators do not supply -- under goTemplateOptions missingkey=error that
  # aborts rendering for all 18 Applications, so it must never survive here.
  leftovers = rendered.each_line.select { |l| l.include?('{{') }.map(&:strip)
  assert_eq("arr/values #{app}: no unsubstituted Go-template action survives rendering",
            [], leftovers)

  parsed = begin
    YAML.load(rendered)
  rescue StandardError => e
    # The `{{- if}}`/`{{- end}}` lines must sit at the block-scalar content
    # margin; at file column 0 they terminate the scalar and this is where that
    # shows up.
    fail_assert("arr/values #{app}: rendered helm.values is not parseable YAML: #{e.message}")
    nil
  end
  next if parsed.nil?

  pass("arr/values #{app}: rendered helm.values parses as YAML " \
       "(hasDownloads=#{spec['hasDownloads']})")
  ARR_RENDERED_WORKLOADS[app] = parsed

  image_block = dig_path(parsed, 'controllers.main.containers.main.image')
  assert_eq("arr/values #{app}: image.repository is the app's image", spec['image'],
            dig_path(image_block, 'repository'))
  assert_eq("arr/values #{app}: image.digest carries the promoted digest", ARR_SAMPLE_DIGEST,
            dig_path(image_block, 'digest'))
  assert_eq("arr/values #{app}: the image block has NO `tag` field " \
            '(a digest routed through `tag` is an unparseable reference)',
            false, (image_block || {}).key?('tag'))

  # The digest-vs-tag OUTCOME, derived from app-template's own rule.
  ref = arr_image_ref(image_block)
  assert_eq("arr/values #{app}: derived container image reference is digest-pinned", true,
            ref.to_s.include?("@#{ARR_SAMPLE_DIGEST}"))
  assert_eq("arr/values #{app}: derived reference is NOT the unparseable `repository:sha256:...`",
            false, ref.to_s.include?(":#{ARR_SAMPLE_DIGEST}"))

  assert_eq("arr/values #{app}: service targetPort matches the parameter table",
            spec['port'].to_i, dig_path(parsed, 'service.main.ports.http.targetPort'))
  assert_eq("arr/values #{app}: service publishes port 80", 80,
            dig_path(parsed, 'service.main.ports.http.port'))
  assert_eq("arr/values #{app}: ingress stays disabled (routing is out of scope)", false,
            dig_path(parsed, 'ingress.main.enabled'))

  expected_persistence = spec['hasDownloads'] == 'true' ? %w[config downloads] : %w[config]
  assert_eq("arr/values #{app}: persistence keys follow hasDownloads=#{spec['hasDownloads']}",
            expected_persistence, (dig_path(parsed, 'persistence') || {}).keys.sort)
  if spec['hasDownloads'] == 'true'
    assert_eq("arr/values #{app}: the downloads volume mounts at /data",
              [{ 'path' => '/data' }],
              dig_path(parsed, 'persistence.downloads.advancedMounts.main.main'))
  end

  # No storage class anywhere in the rendered persistence block: the design
  # deliberately relies on each cluster's default StorageClass, and pinning one
  # here would pre-empt the gate that verifies that assumption live.
  assert_eq("arr/values #{app}: no storageClassName in the rendered persistence block", false,
            (dig_path(parsed, 'persistence') || {}).to_json.include?('storageClassName'))
end

# --- 11c. the same values, through the real app-template chart --------------
# The chart lives in an external OCI registry, so this is the one check in the
# suite that can be blocked by something outside the repo. The digest-vs-tag
# OUTCOME is already asserted offline in 11b via app-template's documented rule;
# this raises the bar to the real chart's real output whenever it is reachable,
# and says so loudly when it is not.
ARR_SRC = dig_path(doc(ARR_WORKLOADS), 'spec.template.spec.source') || {}
ARR_CHART_REF = "oci://#{ARR_SRC['repoURL']}/#{ARR_SRC['chart']}"

%w[sonarr prowlarr].each do |app|
  parsed = ARR_RENDERED_WORKLOADS[app]
  next if parsed.nil? || ARR_HELM.nil?

  spec = ARR_APP_TABLE.fetch(app)
  out = nil
  err = nil
  Dir.mktmpdir('arr-values') do |tmp|
    values_path = File.join(tmp, "#{app}.yaml")
    File.write(values_path, YAML.dump(parsed))
    out, err, status = Open3.capture3(ARR_HELM, 'template', app, ARR_CHART_REF,
                                      '--version', ARR_SRC['targetRevision'].to_s,
                                      '-f', values_path)
    out = nil unless status.success?
  end

  if out.nil?
    puts "NOTE: #{ARR_CHART_REF} unreachable for #{app} (#{err.to_s.strip[0, 160]}) -- " \
         'the digest-vs-tag outcome remains asserted offline in section 11b.'
    next
  end

  pass("arr/app-template #{app}: #{ARR_CHART_REF} renders with the generated values")

  images = out.each_line.select { |l| l =~ /^\s+image:\s/ }.map { |l| l.split('image:', 2)[1].strip }
  assert_eq("arr/app-template #{app}: container image is <repository>@<digest>",
            ["#{spec['image']}@#{ARR_SAMPLE_DIGEST}"], images.uniq)
  assert_eq("arr/app-template #{app}: no `<repository>:sha256:...` reference is emitted", [],
            images.select { |i| i.include?(":#{ARR_SAMPLE_DIGEST}") })

  rendered_docs = begin
    YAML.load_stream(out).compact
  rescue StandardError => e
    fail_assert("arr/app-template #{app}: rendered output is not parseable YAML: #{e.message}")
    []
  end
  pvcs = rendered_docs.select { |d| d['kind'] == 'PersistentVolumeClaim' }
  assert_eq("arr/app-template #{app}: PVC count follows hasDownloads=#{spec['hasDownloads']}",
            spec['hasDownloads'] == 'true' ? 2 : 1, pvcs.length)
  downloads_pvc = pvcs.select { |d| dig_path(d, 'metadata.name').to_s.include?('downloads') }
  assert_eq("arr/app-template #{app}: a downloads PVC exists iff hasDownloads is true",
            spec['hasDownloads'] == 'true' ? 1 : 0, downloads_pvc.length)
  assert_eq("arr/app-template #{app}: a /data mount exists iff hasDownloads is true",
            spec['hasDownloads'] == 'true', out.include?('mountPath: /data'))
end

# ---------------------------------------------------------------------------
section '12. arr-stack cross-file contracts'
# ---------------------------------------------------------------------------
# The highest-value section. Every fact below is stated in one file and consumed
# in another, with nothing at either end that errors when they disagree.

# --- 12a. four-way roster agreement ----------------------------------------
ARR_WORKLOAD_LIST = dig_path(doc(ARR_WORKLOADS), 'spec.generators.0.matrix.generators.0.list.elements') || []
ARR_KARGO_LIST    = dig_path(doc(ARR_KARGO), 'spec.generators.0.list.elements') || []

workload_names = ARR_WORKLOAD_LIST.map { |e| e['name'] }.sort
kargo_names     = ARR_KARGO_LIST.map { |e| e['name'] }.sort
env_names       = Dir.glob(File.join(ARR_ENV_DIR, '*')).select { |p| File.directory?(p) }
                     .map { |p| File.basename(p) }.sort

assert_eq('arr/roster: appset-workloads list == the epic parameter table', ARR_APPS, workload_names)
assert_eq('arr/roster: appset-kargo list == the epic parameter table', ARR_APPS, kargo_names)
assert_eq('arr/roster: env/*/ directories == the epic parameter table', ARR_APPS, env_names)
assert_eq('arr/roster: appset-workloads list == appset-kargo list', workload_names, kargo_names)
assert_eq('arr/roster: appset-kargo list == env/*/ directories', kargo_names, env_names)
assert_true('arr/roster: the sixth app is seerr, not the retired overseerr',
            ARR_APPS.include?('seerr') && !ARR_APPS.include?('overseerr'))

# --- 12b. per-app leaf values agree across every source --------------------
ARR_APP_TABLE.each do |app, spec|
  wl = ARR_WORKLOAD_LIST.find { |e| e['name'] == app } || {}
  kg = ARR_KARGO_LIST.find { |e| e['name'] == app } || {}

  assert_eq("arr/params #{app}: appset-workloads image matches the parameter table",
            spec['image'], wl['image'])
  assert_eq("arr/params #{app}: appset-kargo image matches the parameter table",
            spec['image'], kg['image'])
  assert_eq("arr/params #{app}: the two ApplicationSets agree byte-for-byte on the image",
            wl['image'], kg['image'])
  assert_eq("arr/params #{app}: port matches the parameter table", spec['port'], wl['port'])
  assert_eq("arr/params #{app}: hasDownloads matches the parameter table",
            spec['hasDownloads'], wl['hasDownloads'])
  # port/hasDownloads must be STRINGS: `eq .hasDownloads "true"` compares a
  # string, and a YAML boolean would make the conditional silently always-false.
  assert_eq("arr/params #{app}: port and hasDownloads are quoted strings",
            %w[String String], [wl['port'].class.to_s, wl['hasDownloads'].class.to_s])
end

# --- 12c. the 18 release.yaml promotion targets -----------------------------
release_files = Dir.glob(File.join(ARR_ENV_DIR, '*/*/release.yaml')).sort
assert_eq('arr/release: exactly 18 release.yaml promotion targets exist (6 apps x 3 stages)',
          18, release_files.length)

expected_pairs = ARR_APPS.product(ARR_STAGE_ORDER).map { |a, s| "#{a}/#{s}" }.sort
actual_pairs = release_files.map { |f| f.split('/')[-3, 2].join('/') }.sort
assert_eq('arr/release: (app, stage) pairs are the full 6x3 cross-product',
          expected_pairs, actual_pairs)

release_files.each do |f|
  pair = f.split('/')[-3, 2].join('/')
  d = doc(f) || {}
  assert_eq("arr/release #{pair}: `values` is exactly an empty map", {}, d['values'])
  tag = d['imageTag']
  assert_true("arr/release #{pair}: imageTag is a well-formed sha256 digest (#{tag.inspect})",
              tag.is_a?(String) && !(tag =~ DIGEST_RE).nil?)
end

# One shared pre-promotion seed per app: all three stage files identical.
ARR_APPS.each do |app|
  tags = ARR_STAGE_ORDER.map do |stage|
    (doc(File.join(ARR_ENV_DIR, app, stage, 'release.yaml')) || {})['imageTag']
  end
  assert_eq("arr/release #{app}: all three stages share one byte-identical seed digest",
            1, tags.uniq.length)
end
# Different apps are NOT required to agree -- but they must not all be the same
# placeholder either, which would mean nobody resolved real digests.
assert_true('arr/release: apps carry per-app digests, not one shared placeholder',
            ARR_APPS.map { |a| (doc(File.join(ARR_ENV_DIR, a, 'dev', 'release.yaml')) || {})['imageTag'] }
                    .uniq.length > 1)

# --- 12d. the digest binding and its param path ----------------------------
# Inspected STRUCTURALLY (which field is bound to which parameter) rather than by
# text match, so a reordering or a reformat cannot make the check vacuous. The
# literal-text assertion below is the belt to this braces.
ARR_VALUES_TREE = arr_values_as_yaml(ARR_WORKLOAD_VALUES)
arr_image_binding = dig_path(ARR_VALUES_TREE, 'controllers.main.containers.main.image') || {}

assert_eq('arr/binding: app-template `digest` is bound to the top-level `{{.imageTag}}` parameter',
          '{{.imageTag}}', arr_image_binding['digest'])
assert_eq('arr/binding: the image block binds NO `tag` field at all', false,
          arr_image_binding.key?('tag'))
assert_eq('arr/binding: `repository` is bound to the per-app `{{.image}}` parameter',
          '{{.image}}', arr_image_binding['repository'])
assert_eq('arr/binding: the image block binds exactly repository + digest', %w[digest repository],
          arr_image_binding.keys.sort)
assert_match_present('arr/binding: the literal `digest: "{{.imageTag}}"` is present',
                     /^\s*digest:\s*"\{\{\.imageTag\}\}"\s*$/, ARR_WORKLOADS)

# --- 12e. the vendored chart's Argo CD-compatibility markers ---------------
chart_files = Dir.glob(File.join(ARR_CHART_DIR, '**/*')).select { |f| File.file?(f) }.sort
assert_true('arr/chart: the vendored Kargo chart has files to check', chart_files.length >= 5)
missing_marker = chart_files.reject { |f| raw(f).include?('+argocd:skip-file-rendering') }
assert_eq('arr/chart: EVERY file under kargo-chart/ carries +argocd:skip-file-rendering ' \
          '(bootstrap syncs apps/*/argocd with recurse:true and no Helm awareness)',
          [], missing_marker.map { |f| rel(f) })
assert_match_present('arr/chart: project.yaml carries argocd.argoproj.io/sync-wave "-1"',
                     /argocd\.argoproj\.io\/sync-wave:\s*"-1"/,
                     File.join(ARR_CHART_DIR, 'templates/project.yaml'))

# --- 12f. Application name <-> authorized-stage annotation consistency -----
# Kargo's argocd-update step names the Application it nudges, and Argo CD only
# lets it through if that Application's kargo.akuity.io/authorized-stage
# annotation names the same <project>:<stage>. Drift between the two breaks
# promotion silently -- no error surfaces anywhere.
name_tmpl = dig_path(doc(ARR_WORKLOADS), 'spec.template.metadata.name')
annot_tmpl = arr_annotation(doc(ARR_WORKLOADS), 'spec.template.metadata.annotations',
                            'kargo.akuity.io/authorized-stage')
assert_eq('arr/authz: Application name template is arr-<app>-<stage>',
          'arr-{{.name}}-{{.path.basename}}', name_tmpl)
assert_eq('arr/authz: authorized-stage annotation is <app>:<stage>',
          '{{.name}}:{{.path.basename}}', annot_tmpl)

# Both templates must interpolate the SAME two tokens, in the same roles.
def arr_tokens(tmpl)
  tmpl.to_s.scan(/\{\{\.([\w.]+)\}\}/).flatten
end
assert_eq('arr/authz: the name template and the annotation interpolate the same two tokens',
          arr_tokens(name_tmpl), arr_tokens(annot_tmpl))

ARR_RENDERED_KARGO.each do |app, rendered|
  task = rendered.find { |d| d['kind'] == 'PromotionTask' }
  steps = dig_path(task, 'spec.steps') || []

  update = steps.find { |s| s['uses'] == 'argocd-update' }
  target = dig_path(update, 'config.apps.0.name').to_s
  # The Kargo expression survives Helm rendering verbatim; normalise both sides'
  # stage token so the comparison is about the NAME SHAPE, not the syntax.
  normalised_target = target.sub(/\$\{\{\s*ctx\.stage\s*\}\}/, '<STAGE>')
  expected_name = name_tmpl.to_s.sub('{{.name}}', app).sub('{{.path.basename}}', '<STAGE>')
  assert_eq("arr/authz #{app}: the PromotionTask nudges exactly the Application the " \
            'workloads appset generates', expected_name, normalised_target)

  expected_annot = annot_tmpl.to_s.sub('{{.name}}', app).sub('{{.path.basename}}', '<STAGE>')
  assert_eq("arr/authz #{app}: the authorized-stage annotation names this app's Kargo project",
            "#{app}:<STAGE>", expected_annot)

  # The promotion writes the very file the workloads generator discovers.
  yaml_update = steps.find { |s| s['uses'] == 'yaml-update' }
  path = dig_path(yaml_update, 'config.path').to_s.sub(%r{\A\./src/}, '')
  assert_eq("arr/authz #{app}: yaml-update targets apps/arr-stack/env/#{app}/<stage>/release.yaml",
            "apps/arr-stack/env/#{app}/<STAGE>/release.yaml",
            path.sub(/\$\{\{\s*ctx\.stage\s*\}\}/, '<STAGE>'))
  assert_eq("arr/authz #{app}: every stage's promotion target file actually exists", [],
            ARR_STAGE_ORDER.reject do |stage|
              File.file?(File.join(REPO_ROOT, path.sub(/\$\{\{\s*ctx\.stage\s*\}\}/, stage)))
            end)
  assert_eq("arr/authz #{app}: the promotion writes the top-level `imageTag` key", 'imageTag',
            dig_path(yaml_update, 'config.updates.0.key'))
end

# The workloads generator's git-files path must be the same env/<app>/<stage>
# shape the promotion writes to.
assert_eq('arr/authz: the workloads git-files generator discovers env/<app>/*/release.yaml',
          'apps/arr-stack/env/{{.name}}/*/release.yaml',
          dig_path(doc(ARR_WORKLOADS),
                   'spec.generators.0.matrix.generators.1.git.files.0.path'))

# --- 12g. OCI source shape (the InvalidSpecError this epic hit live) -------
assert_eq('arr/oci: source.repoURL carries NO oci:// scheme prefix', false,
          ARR_SRC['repoURL'].to_s.start_with?('oci://'))
assert_true("arr/oci: source.chart is present and non-empty (#{ARR_SRC['chart'].inspect})",
            ARR_SRC['chart'].is_a?(String) && !ARR_SRC['chart'].strip.empty?)
assert_eq('arr/oci: source.repoURL is the registry path only', 'ghcr.io/bjw-s-labs/helm',
          ARR_SRC['repoURL'])
assert_eq('arr/oci: source.chart names the chart separately', 'app-template', ARR_SRC['chart'])
assert_true("arr/oci: source.targetRevision pins a chart version (#{ARR_SRC['targetRevision'].inspect})",
            !ARR_SRC['targetRevision'].to_s.strip.empty?)
# The chart name must not be smuggled into the repoURL under any scheme.
assert_eq('arr/oci: the chart name is not folded into repoURL', false,
          ARR_SRC['repoURL'].to_s.include?(ARR_SRC['chart'].to_s))

# --- 12h. destinations -----------------------------------------------------
assert_eq('arr/dest: workload Applications target demo1/demo2 by NAME, never {{server}}',
          '{{- if eq .path.basename "prod" -}}demo2{{- else -}}demo1{{- end -}}',
          dig_path(doc(ARR_WORKLOADS), 'spec.template.spec.destination.name'))
assert_eq('arr/dest: workload namespace is the per-stage shared namespace',
          'arr-stack-{{.path.basename}}',
          dig_path(doc(ARR_WORKLOADS), 'spec.template.spec.destination.namespace'))
assert_eq('arr/dest: Kargo pipelines land on the kargo cluster', 'kargo',
          dig_path(doc(ARR_KARGO), 'spec.template.spec.destination.name'))
[ARR_WORKLOADS, ARR_KARGO].each do |path|
  assert_eq("arr/dest: #{rel(path)} never sets destination.server", false,
            (dig_path(doc(path), 'spec.template.spec.destination') || {}).key?('server'))
  assert_eq("arr/dest: #{rel(path)} routes both halves through the arr-stack AppProject",
            dig_path(doc(ARR_APPPROJECT), 'metadata.name'),
            dig_path(doc(path), 'spec.template.spec.project'))
end

# ---------------------------------------------------------------------------
section '13. arr-stack negative assertions (out-of-scope + regression guards)'
# ---------------------------------------------------------------------------
# Each negative is paired with a positive assertion that the untouched state is
# genuinely untouched -- a one-directional check misses the whole "someone added
# something they should not have" class of regression.

assert_absent_in_tree('arr/scope: no reference to the deliberately excluded htpc apps ' \
                      '(plex/qbittorrent/rflood/sabnzbd)',
                      /plex|qbittorrent|rflood|sabnzbd/i, arr_files)
assert_absent_in_tree('arr/scope: no kargo-shared or CustomPromotionStep reference',
                      /kargo-shared|CustomPromotionStep/i, arr_files)
assert_absent_in_tree('arr/scope: no `overseerr` reference anywhere (retired upstream image)',
                      /overseerr/i, arr_files)
# ...and the positive half: the roster really is the six intended apps.
assert_eq('arr/scope: the family is exactly the six intended apps',
          %w[bazarr lidarr prowlarr radarr seerr sonarr], ARR_APPS)

# No Stage verification / AnalysisTemplate. Checked structurally on the RENDERED
# documents, plus a key-anchored raw check: `verification` and `AnalysisTemplate`
# both appear in stages.yaml's explanatory COMMENTS, so a prose-level grep would
# false-positive on the very comment that documents their absence.
assert_absent_in_tree('arr/scope: no `verification:` key in the vendored Kargo chart',
                      /^\s*verification:/, chart_files)
assert_absent_in_tree('arr/scope: no AnalysisTemplate kind in the vendored Kargo chart',
                      /^\s*kind:\s*Analysis(Template|Run)\s*$/, chart_files)
ARR_RENDERED_KARGO.each do |app, rendered|
  assert_eq("arr/scope #{app}: no rendered Stage declares a verification block", [],
            rendered.select { |d| d['kind'] == 'Stage' }
                    .select { |d| (d['spec'] || {}).key?('verification') }
                    .map { |d| dig_path(d, 'metadata.name') })
  assert_eq("arr/scope #{app}: no AnalysisTemplate is rendered", [],
            rendered.map { |d| d['kind'] }.select { |k| k.to_s.start_with?('Analysis') })
end

# storageClassName: deliberately absent AND deliberately discussed. "Silently
# absent" and "explicitly deferred" look identical in a diff; the comment is
# what makes the deferral reviewable, so both halves are asserted.
assert_absent_in_tree('arr/scope: no storageClassName is hard-coded anywhere under apps/arr-stack/',
                      /storageClassName/, arr_files)
assert_match_present('arr/scope: the storage-class deferral is documented, not silent',
                     /default StorageClass/i, ARR_WORKLOADS)

# The digest/tag regression, both param paths, both field choices.
assert_match_absent('arr/regress: no `tag: "{{.imageTag}}"` binding',
                    /^\s*tag:\s*"\{\{\.imageTag\}\}"/, ARR_WORKLOADS)
assert_match_absent('arr/regress: no `tag: "{{.values.imageTag}}"` binding',
                    /^\s*tag:\s*"\{\{\.values\.imageTag\}\}"/, ARR_WORKLOADS)
assert_absent_in_tree('arr/regress: the `.values.imageTag` param path appears nowhere ' \
                      '(release.yaml `values` is an empty map; missingkey=error aborts all 18)',
                      /\{\{\.values\.imageTag\}\}/, arr_files)
assert_absent_in_tree('arr/regress: no `imageTag: release` tag-shaped seed survives',
                      /^\s*imageTag:\s*"?release"?\s*$/, arr_files)
assert_eq('arr/regress: every imageTag is digest-shaped, never empty or tag-shaped', [],
          release_files.reject { |f| (doc(f) || {})['imageTag'].to_s =~ DIGEST_RE }
                       .map { |f| rel(f) })

# The OCI shape regression, as a flat substring sweep over the whole file --
# catches an `oci://` that lands somewhere the structural check above does not
# look (a comment-turned-code, a second source, a values leaf).
assert_match_absent('arr/regress: no `oci://` substring anywhere in appset-workloads.yaml',
                    %r{oci://}, ARR_WORKLOADS)
assert_absent_in_tree('arr/regress: no `oci://` substring anywhere under apps/arr-stack/',
                      %r{oci://}, arr_files)

# bootstrap/ byte-identity. The positive half of "arr-stack never reaches into
# bootstrap": asserted against git history, not just by grepping arr-stack for
# the word "bootstrap".
arr_first_commit = (git_out('log', '--format=%H', '--reverse', '--', 'apps/arr-stack') || '')
                   .lines.first.to_s.strip
epic_base = arr_first_commit.empty? ? nil : git_out('rev-parse', "#{arr_first_commit}^").to_s.strip
if epic_base.nil? || epic_base.empty?
  fail_assert('arr/bootstrap: could not derive the epic base commit from git history, so the ' \
              'byte-identity check did not run')
else
  pass("arr/bootstrap: epic base commit derived from git history (#{epic_base[0, 12]})")
  touched = (git_out('diff', '--name-only', "#{epic_base}..HEAD", '--', 'bootstrap/') || '')
            .split("\n").reject(&:empty?)
  assert_eq('arr/bootstrap: every file under bootstrap/ is byte-identical to the epic base ' \
            '(this epic never adds app-specific config to the fleet-wide discovery layer)',
            [], touched)
end

# ...and the positive half again, structurally: the discovery layer still is
# what it was, so "unchanged" is not vacuously true because the files vanished.
{ 'bootstrap/fleet-argocd-apps.yaml' => ['ApplicationSet', 'fleet-argocd-apps', 'apps/*/argocd'],
  'bootstrap/fleet-kargo-apps.yaml' => ['ApplicationSet', 'fleet-kargo-apps', 'apps/*/kargo'],
  'bootstrap/infra-apps.yaml' => ['ApplicationSet', 'infra-apps', 'infrastructure/*/argocd'] }
  .each do |relpath, (kind, name, path)|
  full = File.join(REPO_ROOT, relpath)
  assert_file("arr/bootstrap: #{relpath} still exists", full)
  assert_yaml("arr/bootstrap: #{relpath} is still a #{kind}", full, 'kind', kind)
  assert_yaml("arr/bootstrap: #{relpath} is still named #{name}", full, 'metadata.name', name)
  assert_yaml("arr/bootstrap: #{relpath} still discovers #{path}", full,
              'spec.generators.0.git.directories.0.path', path)
end
assert_yaml('arr/bootstrap: fleet-platform-aoa.yaml is still the root Application',
            File.join(REPO_ROOT, 'bootstrap/fleet-platform-aoa.yaml'), 'kind', 'Application')

# arr-stack ships no Kargo directory: its pipelines come from appset-kargo.yaml,
# not from bootstrap's apps/*/kargo discovery. If a kargo/ directory ever
# appeared here, bootstrap would generate a SECOND, conflicting Application.
assert_eq('arr/bootstrap: apps/arr-stack/ has no kargo/ directory for bootstrap to discover',
          false, File.directory?(File.join(ARR_DIR, 'kargo')))

# ---------------------------------------------------------------------------
section '14. arr-stack repo-wide name collision check'
# ---------------------------------------------------------------------------
# Argo CD Application, AppProject, and Kargo Project names are namespace-scoped
# but SHARED across this whole fleet, so a collision with akkoma/soju (or with
# anything bootstrap generates) means two owners fighting over one object.

# Everything arr-stack will create, expanded from its own templates.
arr_generated = ['arr-stack',                                        # AppProject
                 'arr-stack-workloads', 'arr-stack-kargo',           # ApplicationSets
                 "argocd-#{File.basename(ARR_DIR)}"]                 # bootstrap wrapper
arr_generated += ARR_APPS.map { |a| "kargo-arr-#{a}" }               # 6 pipeline Applications
arr_generated += ARR_APPS.product(ARR_STAGE_ORDER).map { |a, s| "arr-#{a}-#{s}" } # 18 workloads
arr_kargo_projects = ARR_APPS.dup                                    # 6 Kargo Projects

# 1 AppProject + 2 ApplicationSets + 1 bootstrap wrapper, then one pipeline
# Application and three workload Applications per app.
assert_eq('arr/collide: arr-stack expands to exactly the names its templates can produce',
          4 + (ARR_APPS.length * (1 + ARR_STAGE_ORDER.length)), arr_generated.length)
assert_eq('arr/collide: arr-stack generates no duplicate names internally', [],
          arr_generated.select { |n| arr_generated.count(n) > 1 }.uniq)

# Every pre-existing name in the repo, discovered rather than listed.
existing_names = []
Dir.glob(File.join(REPO_ROOT, '{apps,bootstrap,infrastructure}/**/*.yaml')).sort.each do |f|
  next if f.start_with?("#{ARR_DIR}/")

  stream = begin
    YAML.load_stream(File.read(f)).compact
  rescue StandardError
    [] # akkoma/soju kargo templates carry Kargo expressions; skipped, not fatal
  end
  stream.each do |d|
    next unless d.is_a?(Hash)

    kind = d['kind']
    name = dig_path(d, 'metadata.name')
    tmpl = dig_path(d, 'spec.template.metadata.name')
    existing_names << name if %w[Application ApplicationSet AppProject Project].include?(kind) && name
    existing_names << tmpl if tmpl
  end
end
# Expand bootstrap's own generator templates over the directories they discover.
Dir.glob(File.join(REPO_ROOT, 'apps/*')).select { |p| File.directory?(p) }.each do |app_dir|
  base = File.basename(app_dir)
  existing_names << "argocd-#{base}" if File.directory?(File.join(app_dir, 'argocd'))
  existing_names << "kargo-#{base}" if File.directory?(File.join(app_dir, 'kargo'))
end
Dir.glob(File.join(REPO_ROOT, 'infrastructure/*')).select { |p| File.directory?(p) }.each do |d|
  existing_names << "infra-#{File.basename(d)}"
end
existing_names = existing_names.compact.reject { |n| n.include?('{{') }.uniq.sort

assert_true("arr/collide: discovered #{existing_names.length} pre-existing fleet object names",
            existing_names.length >= 10)
# `argocd-arr-stack` is arr-stack's OWN bootstrap wrapper, generated from
# apps/arr-stack/argocd -- expected on both sides, so it is not a collision.
collisions = (arr_generated & existing_names) - ["argocd-#{File.basename(ARR_DIR)}"]
assert_eq('arr/collide: no arr-stack Application/AppProject name collides with an existing one',
          [], collisions)
assert_eq("arr/collide: no arr-stack Kargo Project name collides with an existing one",
          [], arr_kargo_projects & existing_names)
# Sanity check that the collision set is not vacuously empty.
assert_true('arr/collide: the discovered name set really includes the pre-existing apps',
            (%w[akkoma soju] - existing_names).empty?)

# ---------------------------------------------------------------------------
section '15. arr-stack project hard-rule / quality-gate checks'
# ---------------------------------------------------------------------------
# The repo's registered lint.quality_gates patterns, applied to this epic.

[ARR_WORKLOADS, ARR_KARGO].each do |path|
  opts = dig_path(doc(path), 'spec.template.spec.syncPolicy.syncOptions') || []
  assert_true("arr/gate: #{rel(path)} syncOptions includes CreateNamespace=true " \
              '(both halves create namespaces that nothing else does)',
              opts.include?('CreateNamespace=true'))
  assert_yaml("arr/gate: #{rel(path)} enables automated prune", path,
              'spec.template.spec.syncPolicy.automated.prune', true)
  assert_yaml("arr/gate: #{rel(path)} enables automated selfHeal", path,
              'spec.template.spec.syncPolicy.automated.selfHeal', true)
end

# No secrets committed: this design has none, so ANY secret-shaped object here
# is a mistake rather than a migration.
assert_absent_in_tree('arr/gate: no Secret or SealedSecret manifest under apps/arr-stack/',
                      /^\s*kind:\s*(Secret|SealedSecret)\s*$/, arr_files)
assert_absent_in_tree('arr/gate: no stringData/encryptedData block under apps/arr-stack/',
                      /^\s*(stringData|encryptedData):/, arr_files)
assert_absent_in_tree('arr/gate: no credential-shaped literal under apps/arr-stack/',
                      /^\s*(password|token|apiKey|secretKey|adminPassword):\s*\S/i, arr_files)

# skip-file-rendering, sync-wave, and authorized-stage are each re-asserted in
# section 12; the gate here is that all three are present at once, since each
# one alone is insufficient.
assert_eq('arr/gate: skip-file-rendering + sync-wave + authorized-stage are ALL present',
          [true, true, true],
          [missing_marker.empty?,
           !(raw(File.join(ARR_CHART_DIR, 'templates/project.yaml')) =~ /sync-wave:\s*"-1"/).nil?,
           !annot_tmpl.to_s.empty?])

# promote-loop guard: the promotion pushes a commit to main, and the workloads
# generator watches that repo. If the Warehouse ALSO subscribed to git, that
# commit would mint new Freight and promote again, forever. It subscribes only
# to an image, so the loop cannot close.
ARR_RENDERED_KARGO.each do |app, rendered|
  subs = dig_path(rendered.find { |d| d['kind'] == 'Warehouse' }, 'spec.subscriptions') || []
  assert_eq("arr/gate #{app}: the Warehouse subscribes ONLY to an image, never to git " \
            '(a git subscription would close a promote loop on its own commits)',
            [%w[image]], subs.map { |s| s.keys.sort })
end

# `never add app-specific config`: the fleet-wide discovery layer is untouched
# (asserted against git in section 13) and arr-stack adds no per-app template.
assert_eq('arr/gate: one template serves all 18 workloads (no per-app override block)',
          1, [dig_path(doc(ARR_WORKLOADS), 'spec.template')].compact.length)
assert_eq('arr/gate: appset-workloads declares exactly one (matrix) generator', 1,
          (dig_path(doc(ARR_WORKLOADS), 'spec.generators') || []).length)
assert_true('arr/gate: the workloads generator is a matrix of list x git-files',
            (dig_path(doc(ARR_WORKLOADS), 'spec.generators.0') || {}).key?('matrix'))
assert_yaml('arr/gate: appset-workloads opts into goTemplate', ARR_WORKLOADS,
            'spec.goTemplate', true)
assert_eq('arr/gate: appset-workloads sets goTemplateOptions missingkey=error ' \
          '(a typo in a param path must abort, not render an empty string)',
          ['missingkey=error'], dig_path(doc(ARR_WORKLOADS), 'spec.goTemplateOptions'))

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
