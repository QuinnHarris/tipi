require 'spec_helper'

describe Branch do
  context "with base object" do
    before do
      @branch = Branch.create(name: 'Base')
      expect(@branch).to be_an_instance_of(Branch)
    end

    it "node object has activemodel bahavior" do
      node_a = Task.new(name: 'Node A', branch: @branch)
      expect(node_a.persisted?).to be_false
      expect(node_a.to_key).to be_nil
      node_a.save
      expect(node_a.persisted?).to be_true
      expect(keys = node_a.to_key).not_to be_nil
      
      node_b = node_a.new(branch: @branch)
      expect(node_b.persisted?).to be_true
      expect(node_b.to_key).to eq(keys)
    end
  end

  # Use branch pass interface
  it "can add and remove nodes" do
    branch = Branch.create(name: 'Base')
    node_a = Task.create(name: 'Node A', branch: branch)
    expect(node_a).to be_an_instance_of(Task)
    expect(node_a.branch).to eq(branch)

    expect(Task.dataset(branch).all).to eq([node_a])
    node_a_delete = node_a.delete(branch: branch)
    expect(node_a_delete).to be_an_instance_of(Task)
    expect(node_a_delete.version).to be > node_a.version
    expect(Task.dataset(branch).all).to eq([])
    
    expect(Task.dataset(Sequel::Plugins::Branch::Context.new(branch, node_a.version)).all).
      to eq([node_a])
  end

  def bp_match(array)
    array.map do |node, branch|
      node.dup.tap { |n| n.set_context!(branch) }
    end
  end
  
  # Use context interface
  it "can inherit branch views" do
    node_a = node_b = node_c = nil

    br_a = Branch.create(name: 'Branch A') do
      node_a = Task.create(name: 'Node A')
    end

    br_b = br_a.fork(name: 'Branch B') do
      node_b = Task.create(name: 'Node B')
      expect(Task.all).to match_array([node_a, node_b])
    end

    br_a.context do
      expect(Task.all).to match_array([node_a])
    end

    br_c = br_b.fork(name: 'Branch C', version_lock: true) do
      expect(Task.all).to match_array([node_a, node_b])
      node_a_del = node_a.delete
      expect(node_a_del.context).to eq(Sequel::Plugins::Branch::Context.current)
      expect(Task.all).to match_array([node_b])

      expect { br_a.context { } }.to raise_error(BranchContextError, /^Branch found.+but/)
    end

    br_b.context do
      br_a.context do
        node_c = Task.create(name: 'Node C')
        expect(Task.all).to match_array([node_a, node_c])
      end

      expect(Task.all).to match_array([node_a, node_b, node_c])

      expect { Task.create(name: 'Fail', branch: br_c) }.to raise_error(BranchContextError, /^Branch not found for/)
    end

    br_c.context do
      expect(Task.all).to match_array([node_b])

      node_b_del = node_b.delete
      expect(Task.all).to eq([])

      br_c.context(version: node_b_del.version-1) do
        expect(Task.all).to match_array([node_b])

        expect { node_b.delete }.to raise_error(BranchContextError, "Context without version required")

        expect { br_c.context { } }.to raise_error(BranchContextError, /Branch match.+but/)
      end
    end

    # Merge Tests
    br_d = Branch.merge(br_a, br_b, name: 'Merge AB') do
      expect(Task.all)
        .to match_array(bp_match([[node_a, br_a],
                                  [node_a, br_b],
                                  [node_b, br_b],
                                  [node_c, br_a],
                                  [node_c, br_b]]))
      
      node_b_new = node_b.create(name: "Node B v2")
      
      node_b_row = Task.db[:tasks].where(version: node_b.version).first
      node_b_new_row = Task.db[:tasks].where(version: node_b_new.version).first

      expect(node_b_row.delete(:branch_path)).to eq([])
      expect(node_b_new_row.delete(:branch_path)).to eq([br_b.id])
    end

  end

  def expect_connect(src, op, list)
    pri_d = src.associations[op]
    expect(src.send(op)).to match_array(list)
    expect(src.send(op, true)).to match_array(list) if pri_d

    pri_i = src.associations[:"#{op}_edge"]
    expect(src.send("#{op}_edge").map(&op).compact).to match_array(list)
    expect(src.send("#{op}_edge", true).map(&op).compact).to match_array(list) if pri_i
  end

  it "can link nodes with edges" do
    node_a = node_b = node_c = nil
    br_A = Branch.create(name: 'Branch A') do
      node_a = Task.create(name: 'Node A')
      node_b = Task.create(name: 'Node B')

      edge = node_a.add_to(node_b)
      expect(edge).to be_an_instance_of(TaskEdge)
      expect(edge.context).to eq(node_a.context)
      expect(edge.to).to eq(node_b)
      expect(edge.from).to eq(node_a)

      expect_connect(node_a, :to, [node_b])
      expect_connect(node_a, :from, [])

      expect_connect(node_b, :to, [])
      expect_connect(node_b, :from, [node_a])

      expect { node_a.remove_from(node_b) }
        .to raise_error(VersionedError, "Edge add doesn't change edge state")

      expect { node_a.add_to(node_b) }
        .to raise_error(VersionedError, "Edge add doesn't change edge state")
    end

    br_B = br_A.fork(name: 'Branch B') do
      node_c = Task.create(name: 'Node C')
      expect(node_c.add_from(node_a)).to be_an_instance_of(TaskEdge)

      expect_connect(node_a, :to, [node_b, node_c])

      node_b.delete

      expect_connect(node_a, :to, [node_c])
    end

    # Delete should work as its on branch A
    br_A.context do
      node_b.delete
      raise Sequel::Rollback
    end

    br_B.context do
      expect { node_b.delete }
        .to raise_error(VersionedError, "Delete with existing deleted record")
    end

    br_C = br_B.fork(name: 'Branch C') do
      expect_connect(node_a, :to, [node_c])
      node_a.remove_to(node_c)
      expect_connect(node_a, :to, [])
    end

    # node_a has retained br_A context
    expect_connect(node_a, :to, [node_b])

    br_D = Branch.merge(br_A, br_B, name: 'Branch D (A B Merge)') do
      # Node A
      expect { node_a.to }.to raise_error(BranchContextError, /^Object Duplicated/)
      node_a_list = Task.where(name: 'Node A').all
      expect(Task.where(record_id: node_a.record_id).all).to match_array(node_a_list)
      expect(node_a_list).to eq(bp_match([[node_a, br_A], [node_a, br_B]]))
      node_a_A, node_a_B = node_a_list.sort_by { |n| n.branch_path }
      expect(node_a_A).to_not eq(node_a_B)

      # expect_connect fails here
      expect_connect(node_a_A, :to, bp_match([[node_b, br_A]]))
      expect_connect(node_a_B, :to, bp_match([[node_c, br_B]]))
      node_a_list.each { |node_a| expect_connect(node_a, :from, []) }

      # Node B
      # In this case the branch suggests it can be duplicated but node_b is removed
      # in branch b so it is not duplicated.  Have it check? or feature bloat
      expect { node_b.to }.to raise_error(BranchContextError, /^Object Duplicated/)
      node_b_list = Task.where(name: 'Node B').all
      expect(node_b_list).to eq(bp_match([[node_b, br_A]]))
      expect_connect(node_b_list.first, :to, [])
      expect_connect(node_b_list.first, :from, [node_a_A])

      # Node C
      expect_connect(node_c, :to, [])
      expect_connect(node_c, :from, [node_a_B])

      # Edge in this branch
      expect(node_a_A.add_to(node_c)).to be_an_instance_of(TaskEdge)
      expect_connect(node_a_A, :to, [node_b, node_c])
      expect_connect(node_c, :from, [node_a_A, node_a_B])

      # Modify
      expect { node_a.new(name: 'Node A v2') }.to raise_error(BranchContextError, /^Object Duplicated/)
      expect(node_a_A.context).to eq(Sequel::Plugins::Branch::Context.current)
      node_a_A_new = node_a_A.create(name: 'Node A v2')

      node_a_list = Task.where(record_id: node_a.record_id).all
      expect(node_a_list).to eq([node_a_A_new, node_a_B])
    end
  end

  it "can make interbranch edges" do
    node_a = node_b = node_c = nil
    br_a = Branch.create(name: 'Branch A') do
      node_a = Task.create(name: 'Node A')
    end

    br_b = Branch.create(name: 'Branch B') do
      node_b = Task.create(name: 'Node B')
      node_b.add_from_inter(node_a)
      expect(node_b.from_inter).to eq([node_a])
    end

    br_a.context do
      expect(node_a.to_inter).to eq([node_b])
      node_c = Task.create(name: 'Node C')
      node_a.add_to_inter(node_c)
      expect(node_a.to_inter).to match_array([node_b, node_c])
    end

    br_c = br_a.fork(name: 'Branch C (of A)') do
      node_c.delete
      expect(node_a.to_inter).to eq([node_b])
    end

    br_a.context do
      expect(node_a.to_inter).to match_array([node_b, node_c])
    end

    br_d = Branch.merge(br_b, br_c, name: 'Branch D (of B C)') do
      node_b.delete
      expect(node_a.to_inter).to eq([])
    end
  end

end
