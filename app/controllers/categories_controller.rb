Task
Branch

class CategoriesController < ApplicationController
  # Show all categories
  # GET /categories
  def index
    context = RootBranch.context(version: params[:version], user: current_user)
    @category = Category.root(context)
    #@prev_version = Task.prev_version(@category.context)
    #@next_version = Task.next_version(@category.context)

    Resource.db.transaction do
      ds = UserResource.access_dataset(current_user)
      UserResource.db.create_table :access, :temp => true, :as => ds, :on_commit => :drop
      @resources = UserResource.db[:access].all
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
    RootBranch.context do
      @parent = Category.where(version: params[:parent]).first
      @category = Category.new
    end
  end

  # Create new category
  # POST /categories
  def create
    RootBranch.context do
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
    @category = @category.new
  end

  # PATCH/PUT /categories/1
  def update
    if @category.create(params[:category])
      redirect_to categories_url, notice: 'Category was successfully updated.'
    else
      render :edit
    end
  end

  # DELETE /categories/1
  def destroy
    @category.delete
    redirect_to categories_url, notice: 'Category was successfully deleted.'
  end
end
