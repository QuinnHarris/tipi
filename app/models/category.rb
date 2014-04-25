class Category < Sequel::Model
  many_to_many :parents,  join_table: :category_relations, :class => self,
  			    left_key: :child_id,  right_key: :parent_id
  many_to_many :children, join_table: :category_relations, :class => self,
  			    left_key: :parent_id, right_key: :child_id

  def self.categories_root
    @@categories_root if @@categories_root
    @@categories_root = self.where(id: 1)
  end
end
