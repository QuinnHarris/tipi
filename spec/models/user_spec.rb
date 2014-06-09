require 'spec_helper'

describe User do
  it "can create a user" do
    user = User.new_with_session(attributes_for(:user), {})

  end
end
