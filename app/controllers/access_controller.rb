class AccessController < ResourcesController
  before_action :set_resource, except: [:index, :new, :create]

  def show
    @access = @project.access_resources
  end

  def search
    query = params[:term]

    # Change to use identifier table and search old versions but present current version

    create = []

    expr = nil
    if /.+@.+\..+/i === query
      expr = Sequel.hstore_op(:data).contains(email: query)
      if res = Mailcheck.new.suggest(query)
        create << res[:full]
        expr = expr | Sequel.hstore_op(:data).contains(email: res[:full])
      end
      create << query
    else
      expr = { :name => /#{query}/i }
    end

    result = UserResource.where(expr)
      .finalize
      .select_append(Sequel.expr(:record_id => @project.access_resources_dataset.select(:record_id)).as(:existing))
      .limit(20).all.map do |res|
      {    op: res.values[:existing] ? 'existing' : 'add',
        value: res.record_id,
        label: res.name,
        email: res.email,
        image: ActionController::Base.helpers.image_url('user-silhouette.png')
      }
    end

    if result.empty? and !create.empty?
      result = create.map do |email|
        {    op: 'invite',
          label: 'Invite',
          email: email
        }
      end
    end

    respond_to do |format|
      format.json { render :json => result }
    end
  end

  def add
    @project.context do
      user = UserResource.where(record_id: params[:id]).first
      user.add_to(@project)
    end

    respond_to do |format|
      format.json { render :json => {} }
    end
  end

  def invite
    @project.context do
      user = UserResource.create(name: "Invited User",
                                 branch: RootBranch.branch,
                                 user: current_user,
                                 email: params[:email])
      user.add_to(@project)
    end

    respond_to do |format|
      format.json { render :json => {} }
    end
  end

  def remove
    @project.context do
      user = UserResource.where(record_id: params[:id]).first
      user.remove_to(@project)
    end

    respond_to do |format|
      format.json { render :json => {} }
    end
  end
end
