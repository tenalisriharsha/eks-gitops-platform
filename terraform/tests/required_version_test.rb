#!/usr/bin/env ruby
# Regression test for issue #12: every terraform/**/versions.tf claims
# `required_version = ">= 1.7.0"`, but that is only true if the module's own
# code actually works on that version. Terraform core enforces language
# features at parse time (e.g. cross-variable references inside a
# `validation` block only became legal in Terraform 1.9), so the only way to
# prove a `required_version` lower bound is accurate is to run the real
# module through a real Terraform binary pinned to exactly that version.
#
# This test downloads (and caches under the OS temp dir) the Terraform
# binary matching the declared minimum for each module/environment and runs
# the same `terraform init -backend=false && terraform validate` workflow
# `scripts/validate.sh` runs, against a throwaway copy of the repo's
# terraform/ tree. It therefore needs network access to
# releases.hashicorp.com (and, on first run, the Terraform provider
# registry) — unlike the rest of scripts/tests/, which are network-free.
require 'minitest/autorun'
require 'open3'
require 'tmpdir'
require 'fileutils'

REPO_ROOT = File.expand_path('../..', __dir__)
TERRAFORM_SRC = File.join(REPO_ROOT, 'terraform')
BINARY_CACHE_DIR = File.join(Dir.tmpdir, 'eks-gitops-platform-tf-binary-cache')
PLUGIN_CACHE_DIR = File.join(Dir.tmpdir, 'eks-gitops-platform-tf-plugin-cache')

class RequiredVersionTest < Minitest::Test
  def test_vpc_module_matches_its_declared_minimum_version
    assert_module_valid_on_its_declared_minimum('modules/vpc')
  end

  def test_eks_module_matches_its_declared_minimum_version
    assert_module_valid_on_its_declared_minimum('modules/eks')
  end

  def test_irsa_module_matches_its_declared_minimum_version
    assert_module_valid_on_its_declared_minimum('modules/irsa')
  end

  def test_dev_environment_matches_its_declared_minimum_version
    assert_module_valid_on_its_declared_minimum('environments/dev')
  end

  private

  # Copies the whole terraform/ tree (so relative module sources like
  # ../../modules/vpc still resolve) into a scratch dir, downloads the exact
  # Terraform version that `relative_dir`'s versions.tf declares as its
  # minimum, and runs init+validate with it. Fails with the real Terraform
  # error output when the declared minimum doesn't actually work.
  def assert_module_valid_on_its_declared_minimum(relative_dir)
    Dir.mktmpdir('eks-gitops-platform-required-version-') do |scratch|
      terraform_copy = File.join(scratch, 'terraform')
      FileUtils.cp_r(TERRAFORM_SRC, terraform_copy)

      dir = File.join(terraform_copy, relative_dir)
      min_version = parse_required_version_minimum(File.join(dir, 'versions.tf'))
      binary = terraform_binary(min_version)
      FileUtils.mkdir_p(PLUGIN_CACHE_DIR)
      env = { 'TF_PLUGIN_CACHE_DIR' => PLUGIN_CACHE_DIR }

      init_out, init_status = Open3.capture2e(
        env, binary, 'init', '-input=false', '-backend=false', chdir: dir
      )
      assert init_status.success?, <<~MSG
        #{relative_dir}/versions.tf declares `required_version >= #{min_version}`,
        but `terraform init` using an actual Terraform #{min_version} binary failed:

        #{init_out}
      MSG

      validate_out, validate_status = Open3.capture2e(env, binary, 'validate', chdir: dir)
      assert validate_status.success?, <<~MSG
        #{relative_dir}/versions.tf declares `required_version >= #{min_version}`,
        but `terraform validate` using an actual Terraform #{min_version} binary failed:

        #{validate_out}
      MSG
    end
  end

  def parse_required_version_minimum(versions_tf_path)
    content = File.read(versions_tf_path)
    match = content.match(/required_version\s*=\s*"\s*>=\s*(\d+\.\d+\.\d+)/)
    raise "could not find a `required_version = \">= X.Y.Z\"` constraint in #{versions_tf_path}" unless match

    match[1]
  end

  def terraform_binary(version)
    FileUtils.mkdir_p(BINARY_CACHE_DIR)
    binary_path = File.join(BINARY_CACHE_DIR, "terraform-#{version}-#{host_os}-#{host_arch}")
    return binary_path if File.executable?(binary_path)

    Dir.mktmpdir('eks-gitops-platform-tf-download-') do |download_dir|
      zip_name = "terraform_#{version}_#{host_os}_#{host_arch}.zip"
      zip_path = File.join(download_dir, zip_name)
      url = "https://releases.hashicorp.com/terraform/#{version}/#{zip_name}"

      _out, status = Open3.capture2e('curl', '-sL', '-o', zip_path, url)
      raise "failed to download #{url}" unless status.success? && File.size?(zip_path)

      _out, status = Open3.capture2e('unzip', '-o', '-q', zip_path, '-d', download_dir)
      raise "failed to unzip #{zip_path}" unless status.success?

      FileUtils.cp(File.join(download_dir, 'terraform'), binary_path)
      FileUtils.chmod('+x', binary_path)
    end

    binary_path
  end

  def host_os
    case RbConfig::CONFIG['host_os']
    when /darwin/ then 'darwin'
    when /linux/ then 'linux'
    else raise "unsupported host_os for this test: #{RbConfig::CONFIG['host_os']}"
    end
  end

  def host_arch
    case RbConfig::CONFIG['host_cpu']
    when /arm|aarch64/ then 'arm64'
    when /x86_64|amd64/ then 'amd64'
    else raise "unsupported host_cpu for this test: #{RbConfig::CONFIG['host_cpu']}"
    end
  end
end
