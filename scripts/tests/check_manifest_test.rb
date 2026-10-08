#!/usr/bin/env ruby
# Black-box tests for scripts/check_manifest.rb: write temp YAML fixtures,
# invoke the real CLI entry point as a subprocess (the same way
# scripts/validate-gitops.sh calls it), and assert on exit status + stderr.
# Pure Ruby stdlib (minitest ships with Ruby) — no network, no cluster.
require 'minitest/autorun'
require 'open3'
require 'tmpdir'
require 'fileutils'
require 'yaml'

CHECKER = File.expand_path('../check_manifest.rb', __dir__)
REPO_ROOT = File.expand_path('../..', __dir__)

class CheckManifestTest < Minitest::Test
  def run_checker(*paths)
    Open3.capture3('ruby', CHECKER, *paths)
  end

  def with_fixture(contents)
    Dir.mktmpdir do |dir|
      path = File.join(dir, 'fixture.yaml')
      File.write(path, contents)
      yield path
    end
  end

  def test_valid_deployment_passes
    with_fixture(<<~YAML) do |path|
      apiVersion: apps/v1
      kind: Deployment
      metadata:
        name: backend
      spec:
        replicas: 1
        selector:
          matchLabels:
            app: backend
        template:
          metadata:
            labels:
              app: backend
          spec:
            containers:
              - name: backend
                image: hashicorp/http-echo:1.0
    YAML
      _out, _err, status = run_checker(path)
      assert status.success?, 'a well-formed Deployment should pass'
    end
  end

  def test_missing_metadata_name_fails
    with_fixture(<<~YAML) do |path|
      apiVersion: v1
      kind: Service
      metadata:
        labels:
          app: backend
      spec:
        ports:
          - port: 8080
    YAML
      _out, err, status = run_checker(path)
      refute status.success?, 'a resource with no metadata.name should fail'
      assert_match(/metadata\.name/, err)
    end
  end

  def test_application_without_source_or_destination_fails
    with_fixture(<<~YAML) do |path|
      apiVersion: argoproj.io/v1alpha1
      kind: Application
      metadata:
        name: broken-app
      spec:
        project: default
    YAML
      _out, err, status = run_checker(path)
      refute status.success?, 'an Application missing spec.source/destination should fail'
      assert_match(/spec\.source/, err)
      assert_match(/spec\.destination/, err)
    end
  end

  def test_valid_application_passes
    with_fixture(<<~YAML) do |path|
      apiVersion: argoproj.io/v1alpha1
      kind: Application
      metadata:
        name: sample-app-backend
        namespace: argocd
      spec:
        project: default
        source:
          repoURL: https://example.com/repo.git
          targetRevision: main
          path: sample-app/backend
        destination:
          server: https://kubernetes.default.svc
          namespace: sample-app
    YAML
      _out, _err, status = run_checker(path)
      assert status.success?, 'a well-formed Application should pass'
    end
  end

  def test_deployment_without_containers_fails
    with_fixture(<<~YAML) do |path|
      apiVersion: apps/v1
      kind: Deployment
      metadata:
        name: backend
      spec:
        selector:
          matchLabels:
            app: backend
        template:
          metadata:
            labels:
              app: backend
          spec:
            containers: []
    YAML
      _out, err, status = run_checker(path)
      refute status.success?, 'a Deployment with no containers should fail'
      assert_match(/spec\.template\.spec\.containers/, err)
    end
  end

  def test_service_without_ports_fails
    with_fixture(<<~YAML) do |path|
      apiVersion: v1
      kind: Service
      metadata:
        name: cache
      spec:
        selector:
          app: cache
    YAML
      _out, err, status = run_checker(path)
      refute status.success?, 'a Service with no ports should fail'
      assert_match(/spec\.ports/, err)
    end
  end

  def test_syntax_error_fails
    with_fixture("apiVersion: v1\nkind: [unterminated\n") do |path|
      _out, err, status = run_checker(path)
      refute status.success?, 'invalid YAML syntax should fail'
      assert_match(/syntax error/, err)
    end
  end

  def test_multi_document_stream_checks_every_document
    with_fixture(<<~YAML) do |path|
      apiVersion: v1
      kind: Service
      metadata:
        name: cache
      ---
      apiVersion: v1
      kind: Service
      metadata: {}
    YAML
      _out, err, status = run_checker(path)
      refute status.success?, 'the second malformed document in a stream should still be caught'
      assert_match(/metadata\.name/, err)
    end
  end

  def test_non_kubernetes_yaml_is_ignored
    with_fixture("just: a plain\nyaml: file\n") do |path|
      _out, _err, status = run_checker(path)
      assert status.success?, 'YAML without apiVersion/kind should be skipped, not flagged'
    end
  end

  def test_missing_file_reports_error_without_traceback
    Dir.mktmpdir do |dir|
      missing = File.join(dir, 'does-not-exist.yaml')
      _out, err, status = run_checker(missing)
      assert_equal 1, status.exitstatus, 'an unreadable path should fail with exit 1'
      assert_match(/does-not-exist\.yaml: cannot read/, err)
      refute_match(/\.rb:\d+:in /, err, 'should not dump a Ruby backtrace')
    end
  end

  def test_missing_file_does_not_stop_remaining_files_being_checked
    with_fixture(<<~YAML) do |path|
      apiVersion: v1
      kind: Service
      metadata: {}
    YAML
      _out, err, status = run_checker('/nonexistent/first.yaml', path)
      refute status.success?
      assert_match(/first\.yaml: cannot read/, err)
      assert_match(/fixture\.yaml: missing metadata\.name/, err)
    end
  end

  def test_scalar_metadata_reports_missing_name_without_traceback
    with_fixture(<<~YAML) do |path|
      apiVersion: v1
      kind: Service
      metadata: backend
      spec:
        ports:
          - port: 8080
    YAML
      _out, err, status = run_checker(path)
      assert_equal 1, status.exitstatus
      assert_match(/missing metadata\.name/, err)
      refute_match(/\.rb:\d+:in /, err, 'should not dump a Ruby backtrace')
    end
  end

  def test_list_spec_reports_missing_fields_without_traceback
    with_fixture(<<~YAML) do |path|
      apiVersion: apps/v1
      kind: Deployment
      metadata:
        name: backend
      spec: []
    YAML
      _out, err, status = run_checker(path)
      assert_equal 1, status.exitstatus
      assert_match(/missing spec\.selector, spec\.template, spec\.template\.spec\.containers/, err)
      refute_match(/\.rb:\d+:in /, err, 'should not dump a Ruby backtrace')
    end
  end

  def test_real_sample_app_manifests_pass
    manifests = Dir.glob(File.join(REPO_ROOT, 'sample-app', '**', '*.yaml'))
    refute_empty manifests, 'expected sample-app manifests to exist by Phase 4'
    _out, err, status = run_checker(*manifests)
    assert status.success?, "expected all sample-app manifests to pass, got: #{err}"
  end

  def test_real_applications_point_at_a_real_repo
    apps = Dir.glob(File.join(REPO_ROOT, 'gitops', '**', '*.yaml')).flat_map do |path|
      YAML.load_stream(File.read(path)).select { |doc| doc.is_a?(Hash) && doc['kind'] == 'Application' }
    end
    refute_empty apps
    apps.each do |app|
      url = app.dig('spec', 'source', 'repoURL').to_s
      assert_match(%r{\Ahttps://github\.com/[\w.-]+/[\w.-]+\.git\z}, url,
                   "#{app.dig('metadata', 'name')}: repoURL must be a real, syncable git URL")
    end
  end

  def test_real_gitops_apps_manifests_pass
    manifests = Dir.glob(File.join(REPO_ROOT, 'gitops', 'apps', '*.yaml'))
    refute_empty manifests, 'expected gitops/apps child Applications to exist by Phase 4'
    _out, err, status = run_checker(*manifests)
    assert status.success?, "expected all gitops/apps manifests to pass, got: #{err}"
  end
end
