require 'spec_helper'

describe ProjectsController do
  def response_json
    array = ActiveSupport::JSON.decode(response.body)
    expect(array).to be_an_instance_of(Array)
    array.map { |e| e.symbolize_keys }
  end

  def write_request(id, data)
    post :write, { id: id, data: ActiveSupport::JSON.encode(data) }
    response_json
  end

  it "can create and modify project" do
    sign_in create(:user)

    # Create Project
    Resource
    project_attrs = attributes_for(:project)
    post :create, { category: { version: 1 }, project: project_attrs }
    project = assigns(:project)
    expect(project.values).to include(project_attrs)
    expect(response).to redirect_to project_path(project)
    
    # Create Node
    data = (1..2).map do
      node_attr = attributes_for(:task_ajax)
      #    expect(Node).to receive(:create).with(name: node_1_attr[:name]).once

      resp_data = write_request(project.to_param, node_attr)
      expect(resp_data).to have(1).items

      node_data = resp_data.first
      expect(node_data[:id]).to be      
      expect(node_data.except(:id, :record_id, :branch_path, :branch_id, :created_at)).to eq(node_attr)

      node_data
    end

    node_1_id, node_2_id = data.map { |e| e[:id] }

    # Create Edge
    edge_attr = attributes_for(:task_edge_ajax, u: node_1_id, v: node_2_id)
    resp_data = write_request(project.to_param, edge_attr)
    expect(resp_data).to have(1).items

    data << (edge_data = resp_data.first.symbolize_keys)
    expect(edge_data.except(:id, :branch_id, :branch_path, :v_record_id, :v_branch_path, :u_record_id, :u_branch_path, :created_at)).to eq(edge_attr)

    # Retrieve Data
    get :show, { id: project.to_param, format: :json }
    expect(response_json).to match_array(data)

    # Remove Edge
    data.delete(edge_data)
    edge_attr.merge!(op: 'remove')
    resp_data = write_request(project.to_param, edge_attr)
    expect(resp_data).to have(1).items
    expect(resp_data.first.except(:id, :branch_id, :branch_path, :v_record_id, :v_branch_path, :u_record_id, :u_branch_path, :created_at)).to eq(edge_attr)

    # Retrieve Data
    get :show, { id: project.to_param, format: :json }
    expect(response_json).to match_array(data)

    # Remove Node
    node_attr = data.pop
    node_attr.merge!(op: 'remove')
    resp_data = write_request(project.to_param, node_attr)
    expect(resp_data).to have(1).items
    expect(resp_data.first).to eq(node_attr)

    # Retrieve Data
    get :show, { id: project.to_param, format: :json }
    expect(response_json).to match_array(data)

    # Add Node and Edge in one request
    source_id = 1
    node_attr = attributes_for(:task_ajax, cid: source_id)
    edge_attr = attributes_for(:task_edge_ajax, u: node_1_id, cv: source_id)
    request = [node_attr, edge_attr]
    resp_data = write_request(project.to_param, request)
    expect(resp_data).to have(2).items

    node_3_data = resp_data.first
    expect(resp_data.first[:id]).to be
    expect(resp_data.first).to include(node_attr)

    expect(resp_data.last[:v]).to eq(resp_data.first[:id])
    expect(resp_data.last).to include(edge_attr)

    expect(resp_data.first[:created_at]).to eq(resp_data.last[:created_at])

    # Change a nodee
    node_attr = attributes_for(:task_ajax, op: 'change', id: node_3_data[:id])
    resp_data = write_request(project.to_param, node_attr)
    expect(resp_data).to have(1).items
    node_data = resp_data.first
    expect(node_data[:id]).to be > node_attr[:id]
    expect(node_data.except(:id, :created_at))
      .to eq(node_attr.except(:id).merge(node_3_data.slice(:record_id, :branch_path, :branch_id)))

    # Check post_doc interface
    node_attr = attributes_for(:task_ajax)
    post :post_doc, { id: project.to_param, version: node_data[:id], body: node_attr[:doc] }

  end
end
