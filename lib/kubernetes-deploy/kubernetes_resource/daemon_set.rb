# frozen_string_literal: true
require 'kubernetes-deploy/kubernetes_resource/pod_set_base'
module KubernetesDeploy
  class DaemonSet < PodSetBase
    TIMEOUT = 5.minutes
    attr_reader :pods

    def sync(cache)
      super
      @pods = exists? ? find_pods(cache) : []
      @nodes = find_nodes(cache)
    end

    def status
      return super unless exists?
      rollout_data.map { |state_replicas, num| "#{num} #{state_replicas}" }.join(", ")
    end

    def deploy_succeeded?
      return false unless exists?

      considered_pods = @pods.select { |p| @nodes.map(&:name).include?(p.node_name) }
      (rollout_data["desiredNumberScheduled"].to_i == rollout_data["updatedNumberScheduled"].to_i &&
        ((rollout_data["desiredNumberScheduled"].to_i == rollout_data["numberReady"].to_i) ||
          (!considered_pods.empty? && considered_pods.all?(&:ready?)))) &&
      current_generation == observed_generation
    end

    def deploy_failed?
      pods.present? && pods.any?(&:deploy_failed?) &&
      observed_generation == current_generation
    end

    def fetch_debug_logs
      most_useful_pod = pods.find(&:deploy_failed?) || pods.find(&:deploy_timed_out?) || pods.first
      most_useful_pod.fetch_debug_logs
    end

    def print_debug_logs?
      pods.present? # the kubectl command times out if no pods exist
    end

    private

    class Node
      attr_reader :name

      class << self
        def kind
          name.demodulize
        end
      end

      def initialize(definition:)
        @name = definition.dig("metadata", "name").to_s
        @definition = definition
      end
    end

    def find_nodes(cache)
      # FIXME: should this also exclude tainted nodes?
      all_nodes = cache.get_all(Node.kind)

      all_nodes.each_with_object([]) do |node_data, nodes|
        node = Node.new(definition: node_data)
        nodes << node
      end
    end

    def rollout_data
      return { "currentNumberScheduled" => 0 } unless exists?
      @instance_data["status"]
        .slice("updatedNumberScheduled", "desiredNumberScheduled", "numberReady")
    end

    def parent_of_pod?(pod_data)
      return false unless pod_data.dig("metadata", "ownerReferences")
      pod_data["metadata"]["ownerReferences"].any? { |ref| ref["uid"] == @instance_data["metadata"]["uid"] } &&
      pod_data["metadata"]["labels"]["pod-template-generation"].to_i ==
        @instance_data["spec"]["templateGeneration"].to_i
    end
  end
end
