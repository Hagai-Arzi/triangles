module Linkable

  def self.included(klass)
    klass.extend(ClassMethods)
  end

  module ClassMethods

    # has_many_to_many Specifies a many-to-many bi-directional association.
    # Regularly, the has_many_to_many is declared in each side of the association models.
    # It will also work if declared only on one side of the association. However, doing so will
    # not generate the dynamic methods on the other side, making the connections seen from
    # one side only
    #
    # The associations, for all types and collections, are stored together in a single table called 'any_links'.
    # The table contain all links between all instances of any type.
    # Every record represent a link, which contains id and type for each side of the connection,
    # which are called id1, type1, and id2, type2 respectively.
    # Since the links are bi-directional, theoretically, any object can be represented as the left
    # side link (#1) or right side (#2).
    # For simplicity and performance, the links are stored thus the "smallest" type is in the left.
    # Any link betwwen 'Incident' and 'Change' is stored as the Change object in the left, since
    # the string types are 'Change' < 'Incident'.
    # This technique is 'Hidden' and transparent for the has_many_to_many consumer.
    #
    # For association of the same type - (e.g. Incident has_many incidents):
    # do standard declaration in the Class (i.e. has_many_to_many <collection>).
    # In that case, a callbacks of after create and after destroy shall be called in the relevant any_link class.
    # To overcome association methods that skip callbacks (as clear method) we override the delete_all
    # association method of has many by passing a block with the new function.
    # Notice that calling with 'dependent' param in this case shall raise an error since it doesn't have a meaning
    # for once and secondly this param cannot be passed to destroy_all which is the callback that we call.
    #
    # The table should manually generated with a migration such as this:
    #
    #    class CreateAnyLinks < ActiveRecord::Migration
    #      def up
    #        create_table :any_links do |t|
    #          t.integer :id1, null: false
    #          t.string :type1, null: false
    #          t.integer :id2, null: false
    #          t.string :type2, null: false
    #
    #          t.timestamps
    #        end
    #
    #        change_table :any_links do |t|
    #          t.index [:id1, :type1, :id2, :type2], unique: true
    #          t.index [:id1, :type1, :type2]
    #          t.index [:id2, :type2, :type1]
    #        end
    #      end
    #
    #      def down
    #        drop_table :any_links
    #      end
    #    end

    # A set dynamic methods are generated for altering the set of linked objects.
    # They are the same methods as added by has_many decleration.
    # The following methods for retrieval and query of
    # collections of associated objects will be added:
    #
    #   Auto-generated methods
    #   --------------------------------------
    #   others
    #   others=(other,other,...)
    #   other_ids
    #   other_ids=(id,id,...)
    #   others<<
    #   others.push
    #   others.concat
    #   others.build(attributes={})
    #   others.create(attributes={})
    #   others.create!(attributes={})
    #   others.size
    #   others.length
    #   others.count
    #   others.sum(args*,&block)
    #   others.empty?
    #   others.clear
    #   others.delete(other,other,...)
    #   others.delete_all
    #   others.destroy_all
    #   others.find(*args)
    #   others.exists?
    #   others.uniq
    #   others.reset
    #
    # === Options
    #
    # [:class_name]
    #   Specify the class name of the association. Use it only if that name can't be inferred
    #   from the association name. So <tt>has_many_to_many :products</tt> will by default be linked
    #   to the Product class, but if the real class name is SpecialProduct, you'll have to
    #   specify it with this option.
    #
    # === Examples
    #
    # has_many_to_many :authors                             # linked class is Author
    # has_many_to_many :authors, class_name: "Person"       # specify that linked class is Person
    def has_many_to_many(collection, options = {})
      class_name = options[:class_name]
      link_items, foreign_key, source = define_link_class(class_name || collection)
      has_many link_items, foreign_key: foreign_key
      if !identical_source_collection_class(class_name || collection)
        has_many collection, { through: link_items, source: source, dependent: :destroy }.merge(options)
      else
        has_many collection, through: link_items, source: source, dependent: :destroy do
          def delete_all(dependent = nil)
            if dependent.present?
              raise "The dependency is not supported nor relevant to the case of has_many_to_many since the relation is through association table any_links!"
            end
            destroy_all
          end
        end
      end
    end

    # has_one_to_many Specifies a one-to-many bi-directional association.
    # The has_one_to_many is declared in one side of the association models. The other side
    # must declare the opposite direction with has_many_to_one decleration.
    # Notice: It differ from has_many_to_many, which will work also if only one side of the association is
    # declared.
    #
    # The has_one_to_many and has_many_to_one use the has_many_to_many to create the relatioships, in the same
    # table, but with restriction to a single connection from the has_one side.
    # It means that the decleration creates plural helper functions as above in additition to the following
    # singular helper functions.
    #
    #   Singular Auto-generated methods
    #   --------------------------------------
    #   other
    #   other=other
    #   other_id
    #   other_id=id
    #
    def has_one_to_many(collection, options = {})
      item = collection.to_s.singularize.to_sym
      has_many_to_many(
        item.to_s.pluralize.to_sym,
        options.merge(before_add: -> (owner, obj) { raise ActiveRecord::RecordNotUnique.new("#{name} can have only one #{obj.class} associated") if owner.send(item).present? })
      )
      Linkable.define_singular_accessors(self, item, collection)
    end

    def has_many_to_one(collection, options = {})
      has_many_to_many(collection, options.merge(before_add: -> (_owner, obj) { obj.send(name.demodulize.underscore.pluralize).clear }))
    end

    def identical_source_collection_class(collection_or_class)
      name == collection_or_class.to_s.singularize.classify
    end

    def define_link_class(collection)
      klass1 = name
      klass2 = collection.to_s.singularize.classify
      model1 = name.demodulize.underscore
      model2 = collection.to_s.demodulize.singularize.underscore
      foreign_key = :id1
      source = (klass1 == klass2 ? model2 + "_ghost" : model2).to_sym
      model1, model2, klass1, klass2, foreign_key = model2, model1, klass2, klass1, :id2 if model1 > model2
      klass_name = "#{model1}_#{model2}_link".classify
      model2 = source if klass1 == klass2

      define_class(klass_name, ActiveRecord::Base) do
        if klass1 == klass2
          attr_accessor :duplicated_relation
          after_create :create_opposite_relation
          after_destroy :destroy_opposite_relation
        end

        self.table_name = 'any_links'

        belongs_to model1.to_sym, foreign_key: :id1, class_name: klass1
        belongs_to model2.to_sym, foreign_key: :id2, class_name: klass2

        default_scope { where(type1: klass1, type2: klass2) }

        def create_opposite_relation
          if !duplicated_relation && id2 != id1
            self.class.create!(type1: type1, id1: id2, type2: type1, id2: id1, duplicated_relation: true)
          end
        end

        def destroy_opposite_relation
          self.class.find_by(type1: type1, type2: type2, id1: id2, id2: id1).try(:destroy)
        end
      end

      [klass_name.underscore.pluralize.to_sym, foreign_key, source]
    end

    def define_class(klass_name, ancestor, &block)
      if !const_defined?(klass_name)
        klass = Class.new(ancestor, &block)
        Object.const_set(klass_name, klass)
      end
    end
  end

  def self.define_singular_accessors(model, item, plural_name)
    mixin = model.generated_association_methods
    define_readers(mixin, item, plural_name)
    define_writers(mixin, item, plural_name)
    define_readers(mixin, "#{item}_id", "#{item}_ids")
    define_writers(mixin, "#{item}_id", "#{item}_ids")
  end

  def self.define_readers(mixin, name, plural_name)
    mixin.class_eval <<-CODE, __FILE__, __LINE__ + 1
      def #{name}(*args)
        send("#{plural_name}")[0]
      end
    CODE
  end

  def self.define_writers(mixin, name, plural_name)
    mixin.class_eval <<-CODE, __FILE__, __LINE__ + 1
      def #{name}=(value)
        value.nil? ? send("#{plural_name}=", []) : send("#{plural_name}=", [value])
      end
    CODE
  end
end

ActiveRecord::Base.send(:include, Linkable)
