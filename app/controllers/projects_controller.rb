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

  before_action :set_project, except: [:index, :new, :create, :branch]
  private
  def set_project
    project = Project.dataset(ViewBranch.public)
      .where(version: Integer(params[:id])).first
    # All operations in the branch of this project
    @project = project.with_this_context
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
    project = Project.dataset(ViewBranch.public)
      .where(version: Integer(params[:id])).first
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
        @from.add_to(@to)
        # Remove from project, possibly full remove from db
        #if from.from.include?(@project)

        when 'remove'
        # Add to project if abandoned
        @from.remove_to(@to)
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
      nodes: @nodes.map { |n| { id: n.version, value: {  name:  n.name } } },
      edges: @edges
    }

    respond_to do |format|
      format.xml  { render  :xml => data }
      format.json { render :json => data }
    end
  end

  # GET request at /projects/NUMBER.json (calls show below)
  #   returns an array of objects each with the following format.
  # Message Format:
  #   { 'type': 'node' or 'edge',   // Type of object
  #       'op': 'add' or 'remove',  // Operation on object
  #    . . .
  #   If type is 'node':
  #       'id': NUMBER,             // Unique identifier for object
  #     'name': STRING,             // Name of node
  #    . . .
  #   If type is 'edge':
  #        'u': NUMBER,             // Refers to 'id' of an existing node
  #        'v': NUMBER,             // Refers to 'id' of an existing node
  #   }
  #
  # Currently each id is a NUMBER which is unique for a given project but this
  # is likely to change to an array of NUMBERs that is unique to the entire db.
  #
  # The URL should be determined from the 'data-path' attribute of the
  # div#nodes-container.  For show append a .json to that path or requesting
  # a json mime type without .json is likely to work.
  def show
    respond_to do |format|
      format.html {  }
      format.json do
        get_data
        
        data = []
        data += @nodes.map { |n| { type: :node,
                                   op: :add,
                                   id: n.version,
                                   name: n.name } }
        data += @edges.map { |h| { type: :edge,
                                   op: :add }.merge(h) }
        
        render :json => data
      end
    end
  end 

  # POST request at /projects/NUMBER/write (calls write below)
  # Append 'write' to the 'data-path' attribute to get URL
  # Uses the same message format above passed to the 'data' parameter either an
  # individual object or an array of objects.
  # Must format data parameter as a valid JSON string
  # Will return an array of objects in the same format as show
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

        unless %w(add remove).include?(op)
          raise "Expected op to be add or remove: #{op}"
        end

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
