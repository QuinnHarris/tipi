Branch
Node

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

  # GET request at /projects/NUMBER/search{.json}?q=QUERY
  # accepts q parameter for search string and local if it should only search the
  # current project
  # For HTML response returns an UL (unordered list) with LI for each result
  # For JSON response returns just like show without type or op
  def search
    if params[:local]
      ds = Node.dataset(@project.context)
    else
      ds = Node.dataset.finalize
    end

    @results =
        ds.clone(:from => ds.opts[:from] +
                      [Sequel.lit(["plainto_tsquery(",
                                   '::regconfig, ', ') query'],
                                  'english', params[:q])])
        .where(Sequel.lit('tsv @@ query'))
        .select_append(Sequel.lit('ts_rank_cd(tsv, query)'))
        .limit(10)
        .all

    if @results.empty?
      # No results just use substring matching
      @results =
          ds.where(Sequel.like(:name, /#{params[:q]}/i))
          .limit(10)
          .all
    end

    respond_to do |format|
      format.html { render partial: 'search', collection: @results }
      format.json { render :json => @results.map { |n| n.client_values } }
    end
  end

  # GET request at /projects/NUMBER.json (calls show below)
  #   returns an array of objects each with the following format.
  # Message Format:
  #   {     'type': 'node' or 'edge',             // Type of object
  #           'op': 'add', 'change' or 'remove',  // Operation on object
  #           'id': INTEGER,   // Depreciated, use version (CHANGE PENDING)
  #      'version': INTEGER,   // Unique server identifier for object
  #    'branch_id': INTEGER,   // Branch identifier
  #   'created_at': DATETIME   // Date and time object was created
  #    . . .
  #   If type is 'node':
  #          'cid': ANYTHING,  // Unique client session identifier
  #    'record_id': INTEGER,   // Unique record identifier, stays same with change
  #  'branch_path': [INTEGER], // Must combine with id or record_id to be globally unique
  #         'name': STRING,    // Name of node
  #          'doc': STRING,    // String of document
  #    . . .
  #   If type is 'edge':
  #            'u': INTEGER,   // Refers to 'id' of an existing node
  #  'u_record_id': INTEGER,   // Refers to 'record_id' of an existing node
  #'u_branch_path': INTEGER,   // Refers to 'branch_path' of an existing node
  #           'cu': ANYTHING   // Refers to 'cid' of an existing node
  #            'v': INTEGER,   // Refers to 'id' of an existing node
  #  'v_record_id': INTEGER,   // Refers to 'record_id' of an existing node
  #'v_branch_path': INTEGER,   // Refers to 'branch_path' of an existing node
  #           'cv': ANYTHING,  // Refers to 'cid' of an existing node
  #   }
  #
  # The current id is the version number so the order of ids represents when
  # that instance of the object was created.
  #
  # The change operation will return a new id.  The server id represents a
  # specific version of an object.  Will later send record_id relating different
  # versions of an object together.
  #
  # The URL should be determined from the 'data-path' attribute of the
  # div#nodes-container.  For show append a .json to that path or requesting
  # a json mime type without .json is likely to work.
  def show
    respond_to do |format|
      format.html {  }
      format.json do
        @edges = []

        @project.context do
          if params[:all]
            @nodes = Node.dataset(nil, no_finalize: true).exclude(:type => 'Project').all
            @edges = Edge.dataset(nil, no_finalize: true).all
          else
            @nodes = Node.exclude(:type => 'Project').all
            node_map = {}
            @nodes.each do |node|
              node_map[node.record_id] = node
            end

            @nodes.each do |n|
              n.to_edge.each do |edge|
                # KLUDGE, associations don't update because objects are frozen
                edge = edge.dup # Because its frozen
                to = node_map[edge.from_record_id]
                next unless to # Edge is still here but node has been deleted
                edge.instance_variable_set('@associations',
                                           to: to,
                                           from: n)
                @edges << edge
              end
            end
          end
        end

        data = []
        data += @nodes.map { |n| n.client_values.merge(type: :node, op: :add) }
        data += @edges.map { |n| n.client_values.merge(type: :edge, op: :add) }

        render :json => data.sort_by { |h| h['created_at'] }
      end
    end
  end

  def post_doc
    node = nil
    @project.context do
      node = Node.where(version: Integer(params[:version])).first
      node = node.create(doc: params[:body])
    end

    render :json => node.client_values
  end

  # POST request at /projects/NUMBER/write (calls write below)
  # Append 'write' to the 'data-path' attribute to get URL
  # Uses the same message format above passed to the 'data' parameter either an
  # individual object or an array of objects.
  # Must format data parameter as a valid JSON string
  # Will return an array of objects in the same format as show
  # Multiple changes can be grouped in an array (within the main array ) so they
  # have the same created_at time to group them as single user actions.
  def write
    data = ActiveSupport::JSON.decode(params[:data])
    if data.is_a?(Array)
      # Group changes by default so they have the smae created_at time
      if data.flatten.length == data.length and data.length <= 4
        data = [data]
      end
    elsif data.is_a?(Hash)
      data = [data]
    else
      raise "Expected Array or Hash"
    end
    session_objects = {}
    response = []
    @project.context do
      response = data.map do |list|
        created_at = Node.dataset.current_datetime
        [list].flatten.map do |hash|
          keys = %w(type op)
          type, op = keys.map do |k|
            v = hash[k]
            raise "Expected #{k} got #{hash.inspect}" unless v
            v.downcase
          end

          unless %w(add remove change).include?(op)
            raise "Expected op to be add or remove: #{op}"
          end

          resp = case type
          when 'node'
            fields = { 'created_at' => created_at}
            if op != 'remove'
              %w(name doc).each do |k|
                next unless hash[k]
                fields[k] = hash[k]
                keys << k
              end
              raise "Expected name or doc" if fields.empty?
            end

            if op == 'add'
              raise "Name required" unless fields['name']
              node = Node.create(fields)
              session_objects[hash['cid']] = node if hash['cid']
            else
              id = hash['id']
              raise "Expected id" unless id
              keys << 'id'

              node = Node.where(version: Integer(id)).first
              if op == 'remove'
                node.delete(fields)
              else
                node = node.create(fields)
              end
            end
            hash.merge(node.client_values)

          when 'edge'
            raise "Change not supported on edge" if op == 'change'
            to, from = %w(u v).map do |k|
              if value = hash[k]
                n = Node.where(version: Integer(value)).first
                raise "Didn't find node #{value}" unless n
                keys << k
              elsif cid = hash["c#{k}"]
                raise "Unexpected session reference on remove" if op == 'remove'
                n = session_objects[cid]
                raise "Couldn't find session object" unless n
                keys << "c#{k}"
              else
                raise "Expected value for #{k} or c#{k}"
              end
              n
            end

            edge = from.send("#{op}_to", to, nil, created_at)
            edge = edge.dup
            edge.instance_variable_set('@associations',
                                       to: to,
                                       from: from)
            hash.merge(edge.client_values)
          else
            raise "Expected type to be Node or Edge"
          end

          unless (unexp = (hash.keys - keys)).empty?
            logger.warn("Unexpected properties #{unexp.join(',')} in #{hash.inspect}")
          end

          resp
        end
      end.flatten
    end

#    respond_to do |format|
#      format.json { render :json => response }
#    end
    render :json => response
  end
end
