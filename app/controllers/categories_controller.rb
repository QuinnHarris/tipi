Task
Branch

class CategoriesController < ApplicationController
  # Show all categories
  # GET /categories
  def index
    #@prev_version = Task.prev_version(@category.context)
    #@next_version = Task.next_version(@category.context)

    # This code isn't entirely correct and probably needs to be redone including
    # dataset and decend calls

    context_opts = {
      :user => current_user,
      :version => params[:version] && Integer(params[:version])
    }

    Resource.db.transaction do
      resources = UserResource.access_dataset_with_categories(context_opts).all

      res_map = Hash.new([])
      resources.each { |r| res_map[r.values[:category_record_id]] += [r] }

      exp_cat = Sequel.expr(:record_id => res_map.keys)
      exp_cat |= Sequel.expr(:user_id => current_user.id) if current_user
      exp_cat &= (Sequel.expr(:version) <= context_opts[:version]) if context_opts[:version]

      context = RootBranch.context(context_opts)
      categories = Category.decend(Category.where(exp_cat).finalize, context).all

      cat_map = {}
      categories.each { |c| cat_map[c.version] = c }
      categories.each do |c|
        child = c.values[:to_version]
        c = cat_map[c.version]
        c.associations[:to] = (c.associations[:to] || []) + (child ? [cat_map[child]] : [])
        if res = res_map[c.record_id]
          c.associations[:resources] = ((c.associations[:resources] || []) + res).uniq
        end
      end

      @category = cat_map[1]

      # Kludgy and buggy find adjacent version
      version = context_opts[:version]
      version = [Category, Project].map do |klass|
        klass.raw_dataset.max(:version)
      end.compact.max unless version

      @prev_version, @next_version = [:max, :min].map do |aspect|
        [Category, Project].map do |klass|
          ds = klass.raw_dataset
            if aspect == :min
              ds = ds.where { |o| o.version > version }
            else
              ds = ds.where { |o| o.version < version }
            end
          ds.send(aspect, :version)
        end.send(aspect)
      end
    end
  end

  # Show all versions of a category
  # GET /categories/{version}
  def show
    @category = Category.where(version: params[:id]).first
  end

  # Show page to create a new category
  # GET /categories/new
  def new
    RootBranch.context(user: current_user) do
      @parent = Category.where(version: params[:parent]).first
      @category = Category.new
    end
  end

  # Create new category
  # POST /categories
  def create
    RootBranch.context(user: current_user) do
      parent = Category.where(version: Integer(params[:parent][:version])).first
      parent.add_child(params[:category])
    end

    redirect_to categories_url, notice: 'Category was successfully created.'
  end
  

  before_action :set_category, only: [:edit, :update, :destroy]
  private
  def set_category
    @category = Category.dataset(RootBranch.context).where(version: params[:id]).first
  end
  public

  # Show page to edit existing category
  # GET /categories/1/edit
  def edit
    RootBranch.context(user: current_user) do
      @category = @category.new
    end
  end

  # PATCH/PUT /categories/1
  def update
    RootBranch.context(user: current_user) do
      if @category.create(params[:category])
        redirect_to categories_url, notice: 'Category was successfully updated.'
      else
        render :edit
      end
    end
  end

  # DELETE /categories/1
  def destroy
    RootBranch.context(user: current_user) do
      @category.delete
    end
    redirect_to categories_url, notice: 'Category was successfully deleted.'
  end
end
