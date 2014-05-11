class Creator::ProjectController < ApplicationController
  before_action :set_project, only: [:node_new, :edge_change, :nodes, :read]
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
  def get_data
    @nodes = []
    @edges = []

    @project.context do
      traverse = @project.to
      until traverse.empty?
        @nodes += traverse
        traverse = traverse.map do |node|
          node.to.find_all do |to|
            @edges << { v: node.version, u: to.version }
            !@nodes.include?(to)
        end
        end.flatten.uniq
      end

      # Get unassociated nodes
      @nodes += Node.exclude(:version => @nodes.map(&:version)).exclude(:type => 'Project').all
    end
  end

  def nodes
    get_data
      
    data = {
      nodes: @nodes.map { |n| { id: n.version, value: {  label:  n.name } } },
      edges: @edges
    }

    respond_to do |format|
      format.xml  { render  :xml => data }
      format.json { render :json => data }
    end
  end

  # Suggested new interface with just read GET request to fetch data
  # and write POST request to write data.  Could be replaced with WebSocket in the future
  # Message Format
  #   type: Type of object (node or edge)
  #     op: Operation on object (add or remove)
  # If type is node
  #     id: Unique identifier for object
  #   name: Name of node
  #   More to come as needed
  # If type is edge
  #    u,v: Refers to id of node
  def read
    get_data

    data = []
    data += @nodes.map { |n| { type: :node, op: :add, id: n.version, name: n.name } }
    data += @edges.map { |h| { type: :node, op: :add }.merge(h) }

    respond_to do |format|
      format.xml  { render  :xml => data }
      format.json { render :json => data }
    end
  end 

  # Pass json string in data parameter
  # Untested
  def write
    data = ActiveSupport.JSON.decode(params[:data])
    raise "Expected Array" unless data.is_a?(Array)
    response = []
    @project.context do
      data.each do |hash|
        type, op = %w(type op).map do |k|
          v = hash.delete(k)
          raise "Expected #{k}" unless k
          k.downcase
        end

        raise "Expected op to be add or remove" unless %w(add remove).included?(op)
        
        resp = { type: type, op: op }
        
        case type
        when 'node'
          name = hash.delete('name')
          raise "Expected name" unless name
          
          if op == 'add'
            node = Node.create(name: name)
            response << resp.merge(id: node.id, name: name) 
          else # remove
            id = hash.delete('id')
            raise "Expected id" unless id
            node = Node.where(version: Integer(id)).first
            node.delete
          end
          
        when 'edge'
          to, from = ['u', 'v'].map do |k|
            Node.where(version: Integer(hash.delete(a))).first
          end
          
          from.send("#{op}_to", to)
          response << resp.merge(u: to, v: from)
        else
          raise "Expected type to be Node or Edge"
        end      
      end
    end

    respond_to do |format|
      format.json { render :json => response }
    end
  end

  def clone
    ViewBranch.public.context do
      project = Project.where(version: Integer(params[:project_id] || params[:id])).first
      new_project = project.clone(name: project.name + "+")
    end

    redirect_to creator_project_nodes_url, notice: 'Project was successfully cloned.'
  end
end
