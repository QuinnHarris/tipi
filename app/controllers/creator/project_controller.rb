class Creator::ProjectController < ApplicationController
  before_action :set_project, only: [:node_new, :edge_change, :nodes]
  private
  def set_project
    project = Project.dataset(ViewBranch.public).where(version: Integer(params[:project_id] || params[:id])).first
    @project = project.with_this_context # All operations in the branch of this project
  end
  public

  # JSON call to create a new node
  # PUT call with name paramater
  # returns id and name
  # creator_project_node_new_path(project, format: :json)
  def node_new
    @project.context do
      @node = @project.add_to(Node.create(name: params[:name]))
    end
    respond_to do |format|
      format.json { render :json => { id: @node.version, name: @node.name } }
    end
  end

  # JSON call to add and remove edges
  # PUT call with to and from and op paramater
  # creator_project_edge_change_path(project, format: :json)
  def edge_change
    @project.context do
      @to, @from = [:to, :from].map do |k|
        Node.where(version: Integer(params[k])).first
      end
      case params[:op]
        when 'add'
        from.add_to(to)
        # Remove from project, possibly full remove from db
        #if from.from.include?(@project)

        when 'remove'
        # Add to project if abandoned
        from.remove_to(to)
      else
        raise "must specify action"
      end
    end
    respond_to do |format|
      format.json { render :json => { to: @to.version, from: @from.version } }
    end
  end

  # or should we use a single json input interface to modify nodes?
  
  # creator_project_nodes_path(project, format: :json) 
  def nodes
    nodes = []
    edges_json = []

    traverse = @project.to
    until traverse.empty?
      nodes += traverse
      traverse = traverse.map do |node|
        node.to.find_all do |to|
          edges_json << { v: node.version, u: to.version }
          !nodes.include?(to)
        end
      end.flatten.uniq
    end

    @data = {
      nodes: nodes.map { |n| { id: n.version, value: {  label:  n.name } } },
      edges: edges_json
    }

    respond_to do |format|
      format.xml  { render  :xml => @data }
      format.json { render :json => @data }
    end
  end

  def clone
    Node.db.transaction do
      project = Project.dataset(ViewBranch.public).where(version: Integer(params[:project_id] || params[:id])).first
      new_project = project.clone(name: project.name + "+")
    end

    redirect_to creator_project_nodes_url, notice: 'Project was successfully cloned.'
  end
end
