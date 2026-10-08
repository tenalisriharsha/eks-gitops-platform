#!/usr/bin/env ruby
# Tests that scripts/validate-gitops.sh and scripts/bootstrap-argocd.sh surface
# the real error when the argo Helm repo can't be added (e.g. no network),
# instead of failing later with helm's misleading "no repositories found".
# Runs the real scripts with stub `helm`/`kubectl`/`ruby` binaries first on
# PATH — no network, no cluster.
require 'minitest/autorun'
require 'open3'
require 'tmpdir'

REPO_ROOT = File.expand_path('../..', __dir__)

class HelmRepoSetupTest < Minitest::Test
  REPO_ADD_ERROR = 'Error: looks like "https://argoproj.github.io/argo-helm" is not a valid chart repository or cannot be reached: Forbidden'

  def with_stubs
    Dir.mktmpdir do |bin|
      stub(bin, 'helm', <<~SH)
        case "$1 $2" in
          "repo add") echo '#{REPO_ADD_ERROR}' >&2; exit 1 ;;
          "repo update") echo 'Error: no repositories found. You must add one before updating' >&2; exit 1 ;;
        esac
        exit 0
      SH
      stub(bin, 'kubectl', 'exit 0')
      # validate-gitops.sh runs the Ruby checks before helm; stub them out so
      # this test exercises only the helm step (and doesn't recurse).
      stub(bin, 'ruby', 'exit 0')
      yield({ 'PATH' => "#{bin}:#{ENV.fetch('PATH')}" })
    end
  end

  def stub(dir, name, body)
    path = File.join(dir, name)
    File.write(path, "#!/bin/sh\n#{body}\n")
    File.chmod(0o755, path)
  end

  def assert_repo_add_error_surfaced(script)
    with_stubs do |env|
      _out, err, status = Open3.capture3(env, File.join(REPO_ROOT, 'scripts', script))
      refute status.success?, "#{script} should fail when the helm repo can't be added"
      assert_includes err, REPO_ADD_ERROR
      refute_match(/no repositories found/, err)
    end
  end

  def test_validate_gitops_surfaces_repo_add_error
    assert_repo_add_error_surfaced('validate-gitops.sh')
  end

  def test_bootstrap_argocd_surfaces_repo_add_error
    assert_repo_add_error_surfaced('bootstrap-argocd.sh')
  end
end
