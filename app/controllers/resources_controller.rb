class ResourcesController < ApplicationController
  private
  def set_resource
    record_id, branch_id = params[:resource_id].split('-')
    Branch.context(Integer(branch_id), user: current_user) do
      @project = Project.access(record_id)
      raise "Project not found" unless @project
    end
  end
  public
end