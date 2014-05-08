require 'spec_helper'

describe Branch do
  context "with base object" do
    before do
      @branch = Branch.create(name: 'Base')
      expect(@branch).to be_an_instance_of(Branch)
    end

    it "node object has activemodel bahavior" do
      node_a = Node.new(name: 'Node A', branch: @branch)
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
    node_a = Node.create(name: 'Node A', branch: branch)
    expect(node_a).to be_an_instance_of(Node)
    expect(node_a.branch).to eq(branch)

    expect(Node.dataset(branch).all).to eq([node_a])
    node_a_delete = node_a.delete(branch)
    expect(node_a_delete).to be_an_instance_of(Node)
    expect(node_a_delete.version).to be > node_a.version
    expect(Node.dataset(branch).all).to eq([])
    
    expect(Node.dataset(BranchContext.new(branch, node_a.version)).all).
      to eq([node_a])
  end
  
  # Use context interface
  it "can inherit branch views" do
    node_a = node_b = node_c = nil

    br_a = Branch.create(name: 'Branch A') do
      node_a = Node.create(name: 'Node A')
    end

    br_b = br_a.fork(name: 'Branch B') do
      node_b = Node.create(name: 'Node B')
      expect(Node.all).to match_array([node_a, node_b])
    end

    br_a.context do
      expect(Node.all).to match_array([node_a])
    end

    br_c = br_b.fork(name: 'Branch C', version_lock: true) do
      expect(Node.all).to match_array([node_a, node_b])
      node_a_del = node_a.delete
      expect(node_a_del.context).to eq(Branch.current)
      expect(Node.all).to match_array([node_b])

      expect { br_a.context { } }.to raise_error(BranchContextError, /^Branch found.+but/)
    end

    br_b.context do
      br_a.context do
        node_c = Node.create(name: 'Node C')
        expect(Node.all).to match_array([node_a, node_c])
      end

      expect(Node.all).to match_array([node_a, node_b, node_c])

      expect { Node.create(name: 'Fail', branch: br_c) }.to raise_error(BranchContextError, /^Branch not found for/)
    end

    br_c.context do
      expect(Node.all).to match_array([node_b])

      node_b_del = node_b.delete
      expect(Node.all).to eq([])

      br_c.context(version: node_b_del.version-1) do
        expect(Node.all).to match_array([node_b])

        expect { node_b.delete }.to raise_error(BranchContextError, "Context without version required")

        expect { br_c.context { } }.to raise_error(BranchContextError, /Branch match.+but/)
      end
    end

    # Merge Tests
    br_d = Branch.merge(br_a, br_b, name: 'Merge AB') do
      expect(Node.all)
        .to match_array([[node_a, br_a],
                         [node_a, br_b],
                         [node_b, br_b],
                         [node_c, br_a],
                         [node_c, br_b]].map do |node, branch|
                          node.dup.tap { |n| n[:branch_path] = [branch.id] }
                        end)
      
      node_b_new = node_b.create(name: "Node B v2")
      
      node_b_row = Node.db[:nodes].where(version: node_b.version).first
      node_b_new_row = Node.db[:nodes].where(version: node_b_new.version).first

      expect(node_b_row.delete(:branch_path)).to eq([])
      expect(node_b_new_row.delete(:branch_path)).to eq([br_b.id])

      # More tests

    end
    
  end

  it "can link nodes with edges" do
    node_a = node_b = node_c = nil
    br_a = Branch.create(name: 'Branch A') do
      node_a = Node.create(name: 'Node A')
      node_b = Node.create(name: 'Node B')
      expect(node_a.add_to(node_b)).to eq(node_b)

      expect(node_a.to).to eq([node_b])
      expect(node_a.from).to eq([])

      expect(node_b.to).to eq([])
      expect(node_b.from).to eq([node_a])
    end
    
    br_a.context do
      # In own context because failure aborts transaction
      expect { node_a.add_to(node_b) }.to raise_error(Sequel::UniqueConstraintViolation, /\"edges_from_record_id_from_branch_path_to_record_id_to/)
    end

    br_b = br_a.fork(name: 'Branch B') do
      node_c = Node.create(name: 'Node C')
      expect(node_c.add_from(node_a)).to eq(node_a)

      expect(node_a.to).to match_array([node_b, node_c])

      node_b.delete

      expect(node_a.to).to eq([node_c])
    end

    br_c = br_b.fork(name: 'Branch C') do
      expect(node_a.to).to eq([node_c])
      node_a.remove_to(node_c)
      expect(node_a.to).to eq([])
    end

    # node_a has retained br_a context
    expect(node_a.to).to eq([node_b])
  end

end
