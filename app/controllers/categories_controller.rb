Task
Branch

class CategoriesController < ApplicationController
  # Show all categories
  # GET /categories
  def index
    #@prev_version = Task.prev_version(@category.context)
    #@next_version = Task.next_version(@category.context)

    Resource.db.transaction do
      resources = UserResource.access_dataset_with_categories(current_user).all

      res_map = Hash.new([])
      resources.each { |r| res_map[r.values[:category_record_id]] += [r] }

      exp_cat = Sequel.expr(:record_id => res_map.keys)
      exp_cat |= Sequel.expr(:user_id => current_user.id) if current_user

      context = RootBranch.context(version: params[:version], user: current_user)
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
