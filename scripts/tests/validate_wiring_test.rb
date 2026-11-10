#!/usr/bin/env ruby
# Regression test for issue #15: the regression test added for issue #12
# (terraform/tests/required_version_test.rb) must actually run as part of
# `make validate-all` (and therefore CI), not just exist as a file someone
# has to remember to run by hand.
#
# This stubs out `ruby`, `terraform`, and `helm` with no-op binaries (so the
# run is fast and needs no network / real Terraform binaries) and drives the
# *real* `make validate-all` entrypoint, recording every `ruby <args>`
# invocation made along the way. It then asserts that one of those
# invocations targeted terraform/tests/required_version_test.rb -- i.e. the
# documented validation flow actually exercises that file, regardless of
# which script/Makefile target is the one that ends up invoking it.
require 'minitest/autorun'
require 'open3'
require 'tmpdir'
require 'fileutils'

REPO_ROOT = File.expand_path('../..', __dir__)

class ValidateWiringTest < Minitest::Test
  def test_make_validate_all_exercises_the_required_version_regression_test
    Dir.mktmpdir('eks-gitops-platform-validate-wiring-') do |scratch|
      stub_bin = File.join(scratch, 'bin')
      FileUtils.mkdir_p(stub_bin)
      ruby_log = File.join(scratch, 'ruby-invocations.log')
      FileUtils.touch(ruby_log)

      write_noop_stub(File.join(stub_bin, 'terraform'))
      write_noop_stub(File.join(stub_bin, 'helm'))
      write_logging_ruby_stub(File.join(stub_bin, 'ruby'), ruby_log)

      env = { 'PATH' => "#{stub_bin}:#{ENV.fetch('PATH')}" }
      out, status = Open3.capture2e(env, 'make', 'validate-all', chdir: REPO_ROOT)

      assert status.success?, "stubbed `make validate-all` was expected to succeed, but failed:\n#{out}"

      invocations = File.read(ruby_log)
      assert_match(
        %r{terraform/tests/required_version_test\.rb},
        invocations,
        "`make validate-all` never invoked `ruby .../terraform/tests/required_version_test.rb`.\n" \
        "ruby invocations actually made:\n#{invocations.empty? ? '(none)' : invocations}"
      )
    end
  end

  private

  def write_noop_stub(path)
    File.write(path, "#!/bin/sh\nexit 0\n")
    FileUtils.chmod(0o755, path)
  end

  def write_logging_ruby_stub(path, log_path)
    File.write(path, <<~SH)
      #!/bin/sh
      echo "$@" >> #{log_path}
      exit 0
    SH
    FileUtils.chmod(0o755, path)
  end
end
