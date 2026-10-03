#!/usr/bin/env ruby
# Structural check for Kubernetes/ArgoCD YAML manifests: valid YAML syntax,
# plus required fields present on anything that looks like a k8s resource.
# No cluster, network, or gems required — uses Ruby's bundled YAML (Psych).
require 'yaml'

status = 0

ARGV.each do |path|
  begin
    docs = YAML.load_stream(File.read(path))
  rescue Psych::SyntaxError => e
    warn "#{path}: YAML syntax error: #{e.message}"
    status = 1
    next
  end

  docs.compact.each do |doc|
    next unless doc.is_a?(Hash)
    next unless doc.key?('apiVersion') && doc.key?('kind')

    missing = []
    missing << 'metadata.name' unless doc.dig('metadata', 'name')

    if doc['kind'] == 'Application' && doc['apiVersion'].to_s.start_with?('argoproj.io')
      missing << 'spec.source' unless doc.dig('spec', 'source')
      missing << 'spec.destination' unless doc.dig('spec', 'destination')
    end

    if doc['kind'] == 'Deployment'
      missing << 'spec.selector' unless doc.dig('spec', 'selector')
      missing << 'spec.template' unless doc.dig('spec', 'template')
      containers = doc.dig('spec', 'template', 'spec', 'containers')
      missing << 'spec.template.spec.containers' if containers.nil? || containers.empty?
    end

    if doc['kind'] == 'Service'
      ports = doc.dig('spec', 'ports')
      missing << 'spec.ports' if ports.nil? || ports.empty?
    end

    unless missing.empty?
      warn "#{path}: missing #{missing.join(', ')}"
      status = 1
    end
  end
end

exit status
