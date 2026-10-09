#!/usr/bin/env ruby
# Structural check for Kubernetes/ArgoCD YAML manifests: valid YAML syntax,
# plus required fields present on anything that looks like a k8s resource.
# No cluster, network, or gems required — uses Ruby's bundled YAML (Psych).
require 'yaml'

# Like Hash#dig, but returns nil instead of raising when an intermediate value
# is a scalar or list (e.g. `metadata: foo` or `spec: []`).
def field(doc, *keys)
  keys.reduce(doc) { |node, key| node.is_a?(Hash) ? node[key] : nil }
end

status = 0

ARGV.each do |path|
  begin
    docs = YAML.load_stream(File.read(path))
  rescue Psych::SyntaxError => e
    warn "#{path}: YAML syntax error: #{e.message}"
    status = 1
    next
  rescue SystemCallError => e
    warn "#{path}: cannot read: #{e.message}"
    status = 1
    next
  end

  docs.compact.each do |doc|
    next unless doc.is_a?(Hash)
    next unless doc.key?('apiVersion') && doc.key?('kind')

    missing = []
    missing << 'metadata.name' unless field(doc, 'metadata', 'name')

    if doc['kind'] == 'Application' && doc['apiVersion'].to_s.start_with?('argoproj.io')
      missing << 'spec.source' unless field(doc, 'spec', 'source')
      missing << 'spec.destination' unless field(doc, 'spec', 'destination')
    end

    if doc['kind'] == 'Deployment'
      missing << 'spec.selector' unless field(doc, 'spec', 'selector')
      missing << 'spec.template' unless field(doc, 'spec', 'template')
      containers = field(doc, 'spec', 'template', 'spec', 'containers')
      missing << 'spec.template.spec.containers' if !containers.is_a?(Array) || containers.empty?
    end

    if doc['kind'] == 'Service'
      ports = field(doc, 'spec', 'ports')
      missing << 'spec.ports' if !ports.is_a?(Array) || ports.empty?
    end

    unless missing.empty?
      warn "#{path}: missing #{missing.join(', ')}"
      status = 1
    end
  end
end

exit status
