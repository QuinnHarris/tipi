class ProjectsController < ApplicationController
  def index

  end

  def new
    @category = Category.where(version: params[:category]).first
    @project = Project.new(branch: ViewBranch.public)
  end

  def create
    ViewBranch.public.context do
      category = Category.where(version: params[:category][:version]).first
      @project = category.add_project(params[:project])
    end

    redirect_to project_path(@project), notice: 'Category was successfully created.'
  end

  before_action :set_project, except: [:index, :new, :create, :branch, :write]
  private
  def set_project
    project = Project.dataset(ViewBranch.public).where(version: Integer(params[:id])).first
    @project = project.with_this_context # All operations in the branch of this project
  end
  public

  def edit
    @project = @project.new
  end

  def update
    @project = @project.with_this_context
    if @project.create(params[:project])
      redirect_to categories_url, notice: 'Project was successfully updated.'
    else
      render :edit
    end
  end

  def clone
    @project = @project.new
  end

  def branch
    project = Project.dataset(ViewBranch.public).where(version: Integer(params[:id])).first
    new_project = project.clone(params[:project])

    redirect_to project_path(project), notice: 'Project was successfully cloned.'
  end

  def destroy
    @project.delete
    redirect_to categories_url, notice: 'Project was successfully deleted'
  end

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
    @edges = []

    @project.context do
      @nodes = Node.exclude(:type => 'Project').all

      @nodes.each do |n|
        n.to.each do |to|
          @edges << { v: n.version, u: to.version }
        end
      end
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
  def show
    respond_to do |format|
      format.html {  }
      format.json do
        get_data
        
        data = []
        data += @nodes.map { |n| { type: :node, op: :add, id: n.version, name: n.name } }
        data += @edges.map { |h| { type: :edge, op: :add }.merge(h) }
        
        render :json => data
      end
    end
  end 

  # Pass json string in data parameter
  # Untested
  def write
    data = ActiveSupport::JSON.decode(params[:data])
    if data.is_a?(Array)
    elsif data.is_a?(Hash)
      data = [data]
    else
      raise "Expected Array or Hash"
    end
    response = []
    @project.context do
      response = data.map do |hash|
        type, op = %w(type op).map do |k|
          v = hash.delete(k)
          raise "Expected #{k} got #{hash.inspect}" unless v
          v.downcase
        end

        raise "Expected op to be add or remove: #{op}" unless %w(add remove).include?(op)
        
        resp = { type: type, op: op }
        
        case type
        when 'node'
          name = hash.delete('name')
          raise "Expected name" unless name
          
          if op == 'add'
            node = Node.create(name: name)
          else # remove
            id = hash.delete('id')
            raise "Expected id" unless id
            node = Node.where(version: Integer(id)).first
            node.delete
          end
          resp.merge(id: node.version, name: name) 
          
        when 'edge'
          to, from = ['u', 'v'].map do |k|
            Node.where(version: Integer(hash.delete(k))).first
          end
          
          from.send("#{op}_to", to)
          resp.merge(u: to.version, v: from.version)
        else
          raise "Expected type to be Node or Edge"
        end      
      end
    end

#    respond_to do |format|
#      format.json { render :json => response }
#    end
    render :json => response
  end
end
