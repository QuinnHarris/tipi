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
      expect(list.map { |e| e[:branch_id] }.uniq.sort
             ).to eq([@branch,left,right,merge].map { |e| e[:id] }.sort)
    end

    # Keep all above as is until all existing tests pass
  end

  it "can fork and merge 2" do
    list =
      [
       root = Branch.create(name: 'Root'),
       left = root.fork(name: 'Left'),
       right = root.fork(name: 'Right', version_lock: true),
       merge = Branch.merge(left, right, name: 'Merge'),
       lock = merge.fork(name: 'Lock', version_lock: true),
       mega_merge = Branch.merge(lock, merge, right, left, root, name: 'Mega Merge')
      ]
    
    list.each { |b| expect(b).to be_an_instance_of(Branch) }

    def traverse(branch, successor_id = nil, depth = 0, version = nil, bp = [])
      list = branch.predecessor_relations.map do |pred|
        traverse(pred.predecessor,
                 branch.id,
                 depth+1,
                 [version, pred.version].compact.min,
                 (branch.predecessor_relations.length > 1) ?
                 (bp + [pred.predecessor_id]) : bp)
      end.flatten
      [{   branch_id: branch.id,
        successor_id: successor_id,
             version: version,
               depth: depth,
         branch_path: bp
      }] + list
    end

    list.each do |branch|
      rows = branch.context_dataset.all
      expect(rows).to match_array(traverse(branch))
    end
  end
end
