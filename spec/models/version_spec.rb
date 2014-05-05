require 'spec_helper'

describe Branch do
  context "with base object" do
    before do
      @branch = Branch.create(name: 'Base')
      expect(@branch).to be_an_instance_of(Branch)
    end

    %w(predecessor successor).each do |aspect|
      it "can add, remove and enumerate #{aspect.pluralize}" do
        expect(@branch.send(aspect.pluralize)).to eq([])
        
        other = Branch.create(name: aspect)
        expect(other).to be_an_instance_of(Branch)
        expect(@branch.send("add_#{aspect}", other)).to eq(other)
        expect(@branch.send(aspect.pluralize)).to eq([other])
        expect(@branch.send(aspect.pluralize, true)).to eq([other])
        
        expect { @branch.send("add_#{aspect}", other) }.to raise_error(Sequel::UniqueConstraintViolation, /\"branch_relations_pkey\"/)
        
        expect(@branch.send("remove_#{aspect}", other)).to eq(other)
        expect(@branch.send(aspect.pluralize)).to eq([])
        expect(@branch.send(aspect.pluralize, true)).to eq([])
      end
    end

    it "prohibits branch cycles" do
      expect { @branch.add_successor(@branch) }.to raise_error(Sequel::DatabaseError, /cycle found/)

      other = @branch
      (1..3).each do |i|
        other = other.fork(name: "Branch #{i}")
      end
      expect { other.add_successor(@branch) }.to raise_error(Sequel::DatabaseError, /cycle found/)
    end
    
    it "can fork and merge" do
      left = @branch.fork(name: 'Left')
      expect(left).to be_an_instance_of(Branch)

      right = @branch.fork(name: 'Right')
      expect(right).to be_an_instance_of(Branch)

      merge = Branch.merge(left, right, name: 'Merge')
      expect(merge).to be_an_instance_of(Branch)

      list = merge.context_dataset.all
      expect(list.map { |e| e[:id] }.uniq)
        .to match_array([@branch,left,right,merge].map { |e| e[:id] })
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

      expect { br_a.context { } }.to raise_error(SubContextError)
    end

    br_b.context do
      br_a.context do
        node_c = Node.create(name: 'Node C')
        expect(Node.all).to match_array([node_a, node_c])
      end

      expect(Node.all).to match_array([node_a, node_b, node_c])

      expect { Node.create(name: 'Fail', branch: br_c) }.to raise_error(SubContextError)
    end

    br_c.context do
      expect(Node.all).to match_array([node_b])

      node_b_del = node_b.delete
      expect(Node.all).to eq([])

      br_c.context(version: node_b_del.version-1) do
        expect(Node.all).to match_array([node_b])

        expect { node_b.delete }.to raise_error(VersionedObjectError)

        expect { br_c.context { } }.to raise_error(SubContextError)
      end
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
      expect { node_a.add_to(node_b) }.to raise_error(Sequel::UniqueConstraintViolation, /\"edges_from_version_to_version_deleted_key\"/)
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
