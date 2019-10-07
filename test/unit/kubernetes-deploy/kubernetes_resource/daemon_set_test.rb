# frozen_string_literal: true
require 'test_helper'

class DaemonSetTest < KubernetesDeploy::TestCase
  include ResourceCacheTestHelper

  OWNER_UID = 'c31a9b4e-e6dd-11e9-8f47-e6322f98393a'

  def test_deploy_not_successful_when_updated_available_does_not_match
    ds_template = build_ds_template(filename: 'daemon_set.yml')
    ds = build_synced_ds(ds_template: ds_template)
    refute_predicate(ds, :deploy_succeeded?)
  end

  def test_deploy_succeeded_not_fooled_by_stale_status
    status = {
      "observedGeneration": 1,
      "numberReady": 2,
      "desiredNumberScheduled": 2,
      "updatedNumberScheduled": 2,
    }
    ds_template = build_ds_template(filename: 'daemon_set.yml', status: status)
    ds = build_synced_ds(ds_template: ds_template)
    refute_predicate(ds, :deploy_succeeded?)
  end

  def test_deploy_failed_ensures_controller_has_observed_deploy
    ds_template = build_ds_template(filename: 'daemon_set.yml', status: { "observedGeneration": 1 })
    ds = build_synced_ds(ds_template: ds_template)
    ds.stubs(:pods).returns([stub(deploy_failed?: true)])
    refute_predicate(ds, :deploy_failed?)
  end

  def test_deploy_passes_when_updated_available_does_match
    status = {
      "currentNumberScheduled": 3,
      "desiredNumberScheduled": 2,
      "numberReady": 2,
      "updatedNumberScheduled": 2,
      "observedGeneration": 2,
    }

    ds_template = build_ds_template(filename: 'daemon_set.yml', status: status)
    ds = build_synced_ds(ds_template: ds_template)
    assert_predicate(ds, :deploy_succeeded?)
  end

  def test_deploy_passes_when_ready_pods_for_one_node
    status = {
      "desiredNumberScheduled": 1,
      "updatedNumberScheduled": 1,
    }
    ds_template = build_ds_template(filename: 'daemon_set.yml', uid: OWNER_UID, generation: 2, status: status)
    pod_template = build_pod_template(filename: 'daemon_set_pod.yml')
    node_template = build_node_template(filename: 'node.yml')
    ds = build_synced_ds(ds_template: ds_template, pod_templates: pod_template, node_templates: node_template)
    assert_predicate(ds, :deploy_succeeded?)
  end

  def test_deploy_passes_when_ready_pods_for_multiple_nodes
    status = {
      "desiredNumberScheduled": 3,
      "updatedNumberScheduled": 3,
      "numberReady": 2,
    }
    ds_template = build_ds_template(filename: 'daemon_set.yml', uid: OWNER_UID, generation: 2, status: status)
    pod_template = build_pod_template(filename: 'daemon_set_pod.yml')
    node_template = build_node_template(filename: 'node.yml')
    ds = build_synced_ds(ds_template: ds_template, pod_templates: pod_template, node_templates: node_template)
    assert_predicate(ds, :deploy_succeeded?)
  end

  def test_deploy_fails_when_not_all_pods_updated
    status = {
      "desiredNumberScheduled": 3,
      "updatedNumberScheduled": 2,
      "numberReady": 2,
    }
    ds_template = build_ds_template(filename: 'daemon_set.yml', uid: OWNER_UID, generation: 2, status: status)
    pod_template = build_pod_template(filename: 'daemon_set_pod.yml')
    node_template = build_node_template(filename: 'node.yml')
    ds = build_synced_ds(ds_template: ds_template, pod_templates: pod_template, node_templates: node_template)
    refute_predicate(ds, :deploy_succeeded?)
  end

  private

  def build_ds_template(filename:, status: {}, uid: nil, generation: nil)
    base_ds_manifest = YAML.load_stream(File.read(File.join(fixture_path('for_unit_tests'), filename))).first
    base_ds_manifest.deep_merge!("status" => status)
    base_ds_manifest['metadata']['uid'] = uid if uid
    base_ds_manifest['spec']['templateGeneration'] = generation if generation
    base_ds_manifest
  end

  def build_pod_template(filename:)
    base_pod_manifest = YAML.load(File.read(File.join(fixture_path('for_unit_tests'), filename)))
    [base_pod_manifest].flatten
  end

  def build_node_template(filename:)
    base_node_manifest = YAML.load(File.read(File.join(fixture_path('for_unit_tests'), filename)))
    if base_node_manifest['kind'] == 'List'
      base_node_manifest['items']
    else
      [base_node_manifest].flatten
    end
  end

  def build_synced_ds(ds_template:, pod_templates: nil, node_templates: nil)
    ds = KubernetesDeploy::DaemonSet.new(namespace: "test", context: "nope", logger: logger, definition: ds_template)
    stub_kind_get("DaemonSet", items: [ds_template])
    stub_kind_get("Pod", items: pod_templates || [])
    stub_kind_get("Node", items: node_templates || [])
    ds.sync(build_resource_cache)
    ds
  end
end
