#!/usr/bin/env ruby
# Tests scripts/check-drift.sh against a stub `argocd` binary (no network, no
# cluster) — the real behaviour (JSON parsing, exit codes, --diff) rather than
# a reimplementation of it.
require 'minitest/autorun'
require 'open3'
require 'tmpdir'
require 'json'

REPO_ROOT = File.expand_path('../..', __dir__)
SCRIPT = File.join(REPO_ROOT, 'scripts', 'check-drift.sh')

class CheckDriftTest < Minitest::Test
  def stub_argocd(dir, apps, diff_output: 'diff-output')
    path = File.join(dir, 'argocd')
    File.write(path, <<~SH)
      #!/bin/sh
      if [ "$1 $2" = "app list" ]; then
        cat <<'JSON'
      #{JSON.generate(apps)}
      JSON
        exit 0
      fi
      if [ "$1 $2" = "app diff" ]; then
        echo '#{diff_output}'
        exit 1
      fi
      echo "unexpected argocd invocation: $*" >&2
      exit 2
    SH
    File.chmod(0o755, path)
  end

  def app(name, sync, health)
    { 'metadata' => { 'name' => name },
      'status' => { 'sync' => { 'status' => sync }, 'health' => { 'status' => health } } }
  end

  def run_with_stub(apps, *args)
    Dir.mktmpdir do |bin|
      stub_argocd(bin, apps)
      Open3.capture3({ 'PATH' => "#{bin}:#{ENV.fetch('PATH')}" }, SCRIPT, *args)
    end
  end

  def test_all_synced_and_healthy_exits_zero
    apps = [app('sample-app-backend', 'Synced', 'Healthy'), app('sample-app-cache', 'Synced', 'Healthy')]
    out, _err, status = run_with_stub(apps)
    assert status.success?
    assert_match(/no drift/, out)
    assert_match(/sample-app-backend\s+Synced\s+Healthy/, out)
  end

  def test_out_of_sync_app_exits_nonzero
    apps = [app('sample-app-backend', 'OutOfSync', 'Healthy'), app('sample-app-cache', 'Synced', 'Healthy')]
    out, err, status = run_with_stub(apps)
    refute status.success?
    assert_match(/sample-app-backend\s+OutOfSync\s+Healthy/, out)
    assert_match(/drift detected/, err)
  end

  def test_unhealthy_app_exits_nonzero
    apps = [app('sample-app-backend', 'Synced', 'Degraded')]
    _out, err, status = run_with_stub(apps)
    refute status.success?
    assert_match(/drift detected/, err)
  end

  def test_diff_flag_runs_app_diff_for_drifted_apps_only
    apps = [app('sample-app-backend', 'OutOfSync', 'Healthy'), app('sample-app-cache', 'Synced', 'Healthy')]
    out, _err, status = run_with_stub(apps, '--diff')
    refute status.success?
    assert_match(/argocd app diff sample-app-backend/, out)
    assert_match(/diff-output/, out)
  end

  def test_missing_argocd_cli_fails_clearly
    skip 'argocd CLI is installed on this machine' if system('command -v argocd >/dev/null 2>&1')
    _out, err, status = Open3.capture3(SCRIPT)
    refute status.success?
    assert_match(/argocd CLI not found/, err)
  end

  def test_help_flag_prints_usage_and_exits_zero
    out, _err, status = Open3.capture3(SCRIPT, '--help')
    assert status.success?
    assert_match(/Usage:/, out)
  end

  def test_unknown_flag_fails_with_usage_error
    _out, err, status = Open3.capture3(SCRIPT, '--bogus')
    refute status.success?
    assert_match(/unknown argument/, err)
  end
end
