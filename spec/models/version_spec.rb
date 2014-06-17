require 'spec_helper'

describe Branch do
  before do
    @user = create(:user)
  end

  context "with base object" do
    before do
      @branch = Branch.create(name: 'Base')
      expect(@branch).to be_an_instance_of(Branch)
    end

    it "node object has activemodel bahavior" do
      node_a = Resource.new(name: 'Node A', branch: @branch, user: @user)
      expect(node_a.persisted?).to be_false
      expect(node_a.to_key).to be_nil
      node_a.save
      expect(node_a.persisted?).to be_true
      expect(keys = node_a.to_key).not_to be_nil
      
      node_b = node_a.new(branch: @branch, user: @user)
      expect(node_b.persisted?).to be_true
      expect(node_b.to_key).to eq(keys)
    end

    # Use branch pass interface
    it "can add and remove nodes" do
      node_a = Resource.create(name: 'Node A', branch: @branch, user: @user)
      expect(node_a).to be_an_instance_of(Resource)
      expect(node_a.branch).to eq(@branch)

      expect(Resource.dataset(@branch).all).to eq([node_a])
      node_a_delete = node_a.delete(branch: @branch, user: @user)
      expect(node_a_delete).to be_an_instance_of(Resource)
      expect(node_a_delete.version).to be > node_a.version
      expect(Resource.dataset(@branch).all).to eq([])

      expect(Resource.dataset(Sequel::Plugins::Branch::Context.new(@branch, node_a.version)).all).
          to eq([node_a])
    end
  end

  def bp_match(array)
    array.map do |node, branch|
      node.dup_with_context(branch)
    end
  end
  
  # Use context interface
  it "can inherit branch views" do
    node_a = node_b = node_c = nil

    br_a = Branch.create(name: 'Branch A', user: @user) do
      node_a = Resource.create(name: 'Node A')
    end

    br_b = br_a.fork(name: 'Branch B', user: @user) do
      node_b = Resource.create(name: 'Node B')
      expect(Resource.all).to match_array([node_a, node_b])
    end

    br_a.context(user: @user) do
      expect(Resource.all).to match_array([node_a])
    end

    br_c = br_b.fork(name: 'Branch C', version_lock: true, user: @user) do
      expect(Resource.all).to match_array([node_a, node_b])
      node_a_del = node_a.delete
      expect(node_a_del.context).to eq(Sequel::Plugins::Branch::Context.current)
      expect(Resource.all).to match_array([node_b])

      expect { br_a.context { } }.to raise_error(BranchContextError, /^Branch found.+but/)
    end

    br_b.context(user: @user) do
      br_a.context do
        node_c = Resource.create(name: 'Node C')
        expect(Resource.all).to match_array([node_a, node_c])
      end

      expect(Resource.all).to match_array([node_a, node_b, node_c])

      expect { Resource.create(name: 'Fail', branch: br_c) }.to raise_error(BranchContextError, /^Branch not found for/)
    end

    br_c.context(user: @user) do
      expect(Resource.all).to match_array([node_b])

      node_b_del = node_b.delete
      expect(Resource.all).to eq([])

      br_c.context(version: node_b_del.version-1) do
        expect(Resource.all).to match_array([node_b])

        expect { node_b.delete }.to raise_error(BranchContextError, "Context without version required")

        expect { br_c.context { } }.to raise_error(BranchContextError, /Branch match.+but/)
      end
    end

    # Merge Tests
    br_d = Branch.merge(br_a, br_b, name: 'Merge AB', user: @user) do
      expect(Resource.all)
        .to match_array(bp_match([[node_a, br_a],
                                  [node_a, br_b],
                                  [node_b, br_b],
                                  [node_c, br_a],
                                  [node_c, br_b]]))
      
      node_b_new = node_b.create(name: "Node B v2")
      
      node_b_row = Resource.db[:resources].where(version: node_b.version).first
      node_b_new_row = Resource.db[:resources].where(version: node_b_new.version).first

      expect(node_b_row.delete(:branch_path)).to eq([])
      expect(node_b_new_row.delete(:branch_path)).to eq([br_b.id])
    end

  end

  def expect_connect(src, op, list)
    pri_d = src.associations[op]
#    expect(src.send(op)).to match_array(list)
    expect(src.send(op, true)).to match_array(list) #if pri_d
  end

  def expect_connect_edge(src, op, list)
    expect_connect(src, op, list)

    pri_i = src.associations[:"#{op}_edge"]
#    expect(src.send("#{op}_edge").map(&op).compact).to match_array(list)
    expect(src.send("#{op}_edge", true).map(&op).compact).to match_array(list) #if pri_i
  end

  it "can link nodes with edges" do
    node_a = node_b = node_c = nil
    br_A = Branch.create(name: 'Branch A', user: @user) do
      node_a = Resource.create(name: 'Node A')
      node_b = Resource.create(name: 'Node B')

      edge = node_a.add_to(node_b)
      expect(edge).to be_an_instance_of(ResourceEdge)
      expect(edge.context).to eq(node_a.context)
      expect(edge.to).to eq(node_b)
      expect(edge.from).to eq(node_a)

      expect_connect_edge(node_a, :to, [node_b])
      expect_connect_edge(node_a, :from, [])

      expect_connect_edge(node_b, :to, [])
      expect_connect_edge(node_b, :from, [node_a])

      expect { node_a.remove_from(node_b) }
        .to raise_error(VersionedError, "Edge add doesn't change edge state")

      expect { node_a.add_to(node_b) }
        .to raise_error(VersionedError, "Edge add doesn't change edge state")
    end

    br_B = br_A.fork(name: 'Branch B', user: @user) do
      node_c = Resource.create(name: 'Node C')
      expect(node_c.add_from(node_a)).to be_an_instance_of(ResourceEdge)

      expect_connect_edge(node_a, :to, [node_b, node_c])

      node_b.delete

      expect_connect_edge(node_a, :to, [node_c])
    end

    # Delete should work as its on branch A
    br_A.context(user: @user) do
      node_b.delete
      raise Sequel::Rollback
    end

    br_B.context(user: @user) do
      expect { node_b.delete }
        .to raise_error(VersionedError, "Delete with existing deleted record")
    end

    br_C = br_B.fork(name: 'Branch C', user: @user) do
      expect_connect_edge(node_a, :to, [node_c])
      node_a.remove_to(node_c)
      expect_connect_edge(node_a, :to, [])
    end

    # node_a has retained br_A context
    expect_connect_edge(node_a, :to, [node_b])

    br_D = Branch.merge(br_A, br_B, name: 'Branch D (A B Merge)', user: @user) do
      # Node A
      # !!! Has to reload association to trigger check, should this be fixed?
      expect { node_a.to(true) }.to raise_error(BranchContextError, /^Object Duplicated/)
      node_a_list = Resource.where(name: 'Node A').all
      expect(Resource.where(record_id: node_a.record_id).all).to match_array(node_a_list)
      expect(node_a_list).to eq(bp_match([[node_a, br_A], [node_a, br_B]]))
      node_a_A, node_a_B = node_a_list.sort_by { |n| n.branch_path }
      expect(node_a_A).to_not eq(node_a_B)

      # expect_connect fails here
      expect_connect_edge(node_a_A, :to, bp_match([[node_b, br_A]]))
      expect_connect_edge(node_a_B, :to, bp_match([[node_c, br_B]]))
      node_a_list.each { |node_a| expect_connect_edge(node_a, :from, []) }

      # Node B
      # In this case the branch suggests it can be duplicated but node_b is removed
      # in branch b so it is not duplicated.  Have it check? or feature bloat
      expect { node_b.to(true) }.to raise_error(BranchContextError, /^Object Duplicated/)
      node_b_list = Resource.where(name: 'Node B').all
      expect(node_b_list).to eq(bp_match([[node_b, br_A]]))
      expect_connect_edge(node_b_list.first, :to, [])
      expect_connect_edge(node_b_list.first, :from, [node_a_A])

      # Node C
      expect_connect_edge(node_c, :to, [])
      expect_connect_edge(node_c, :from, [node_a_B])

      # Edge in this branch
      expect(node_a_A.add_to(node_c)).to be_an_instance_of(ResourceEdge)
      expect_connect_edge(node_a_A, :to, [node_b, node_c])
      expect_connect_edge(node_c, :from, [node_a_A, node_a_B])

      # Modify
      expect { node_a.new(name: 'Node A v2') }.to raise_error(BranchContextError, /^Object Duplicated/)
      expect(node_a_A.context).to eq(Sequel::Plugins::Branch::Context.current)
      node_a_A_new = node_a_A.create(name: 'Node A v2')

      node_a_list = Resource.where(record_id: node_a.record_id).all
      expect(node_a_list).to eq([node_a_A_new, node_a_B])
    end
  end

  it "can make inter context edges" do
    cat_a = nil
    br_a = Branch.create(name: 'Branch A', user: @user) do
      cat_a = Category.create(name: 'Category A')
    end

    res_a = res_b = nil
    br_b = br_a.fork(name: 'Branch B', user: @user) do
      res_a = Resource.create(name: 'Resource A')
      cat_a.add_resource(res_a)
      expect_connect(cat_a, :resources, [res_a])
    end

    br_a.context(user: @user) do
      expect_connect(cat_a, :resources, [res_a])
    end

    br_c = br_a.fork(name: 'Branch C', user: @user) do
      res_b = Resource.create(name: 'Resource B')
      cat_a.add_resource(res_b)
      # INCLUDE FEATURE TO ENUMERATE ONLY IN CONTEXT
      expect_connect(cat_a, :resources, [res_a, res_b])
    end

    br_a.context(user: @user) do
      expect_connect(cat_a, :resources, [res_a, res_b])
    end

    br_d = Branch.create(name: 'Branch D', user: @user) do
      res_c = Resource.create(name: 'Resource C')
      expect { cat_a.add_resource(res_b) }.to raise_error(BranchContextError, /^Branch not found/)
    end
  end

  it "can make inter branch edges" do
    node_a = node_b = node_c = resource_a = nil
    br_a = Branch.create(name: 'Branch A', user: @user) do
      resource_a = Resource.create(name: 'Resource A')
      node_a = Task.create(name: 'Node A', resource: resource_a)
    end

    br_b = Branch.create(name: 'Branch B', user: @user) do
      resource_b = Resource.create(name: 'Resource B')
      node_b = Task.create(name: 'Node B', resource: resource_b)
      node_b.add_from_inter(node_a)
      expect_connect(node_b, :from_inter, [node_a])
    end

    br_a.context(user: @user) do
      expect_connect(node_a, :to_inter, [node_b])
      node_c = Task.create(name: 'Node C', resource: resource_a)
      node_a.add_to_inter(node_c)
      expect_connect(node_a, :to_inter, [node_b, node_c])
    end

    br_c = br_a.fork(name: 'Branch C (of A)', user: @user) do
      node_c.delete
      expect_connect(node_a, :to_inter, [node_b])
    end

    br_a.context(user: @user) do
      expect_connect(node_a, :to_inter, [node_b, node_c])
    end

    br_d = Branch.merge(br_b, br_c, name: 'Branch D (of B C)', user: @user) do
      node_b.delete
      expect_connect(node_a, :to_inter, [])
    end
  end

end
