require 'spec_helper'

describe ProjectsController do
  it "renders the index template" do
    get :index
    expect(response).to render_template('index')
  end

  def response_json
    array = ActiveSupport::JSON.decode(response.body)
    expect(array).to be_an_instance_of(Array)
    array.map { |e| e.symbolize_keys }
  end

  it "can create and modify project" do
    # Create Project
    project_attrs = attributes_for(:project)
    post :create, { category: { version: 1 }, project: project_attrs }
    project = assigns(:project)
    expect(project.values).to include(project_attrs)
    expect(response).to redirect_to project_path(project)
    
    # Create Node
    data = (1..2).map do
      node_attr = attributes_for(:node_ajax)
      #    expect(Node).to receive(:create).with(name: node_1_attr[:name]).once

      post :write, { id: project.version, data: ActiveSupport::JSON.encode(node_attr) }
      resp_data = response_json
      expect(resp_data).to have(1).items

      node_data = resp_data.first.symbolize_keys
      expect(node_data[:id]).to be      
      expect(node_data).to eq({ id: node_data[:id] }.merge(node_attr))
      
      node_data
    end

    node_1_id, node_2_id = data.map { |e| e[:id] }

    # Create Edge
    edge_attr = attributes_for(:edge_ajax, u: node_1_id, v: node_2_id)
    post :write, { id: project.version, data: ActiveSupport::JSON.encode(edge_attr) }
    resp_data = response_json
    expect(resp_data).to have(1).items

    data << (edge_data = resp_data.first.symbolize_keys)
    expect(edge_data).to eq(edge_attr)

    # Retrieve Data
    get :show, { id: project.version, format: :json }
    expect(response_json).to match_array(data)

    # Remove Edge
    data.delete(edge_attr)
    edge_attr.merge!(op: 'remove')
    post :write, { id: project.version, data: ActiveSupport::JSON.encode(edge_attr) }
    resp_data = response_json
    expect(resp_data).to have(1).items
    expect(resp_data.first).to eq(edge_attr)

    # Retrieve Data
    get :show, { id: project.version, format: :json }
    expect(response_json).to match_array(data)

    # Remove Node
    node_attr = data.pop
    node_attr.merge!(op: 'remove')
    post :write, { id: project.version, data: ActiveSupport::JSON.encode(node_attr) }
    resp_data = response_json
    expect(resp_data).to have(1).items
    expect(resp_data.first).to eq(node_attr)

    # Retrieve Data
    get :show, { id: project.version, format: :json }
    expect(response_json).to match_array(data)
  end
end
