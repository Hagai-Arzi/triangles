require 'spec_helper'

describe Linkable do

  class Reader < ActiveRecord::Base
  end

  class Library < ActiveRecord::Base
  end

  module AModule
    class Book < ActiveRecord::Base
      has_many_to_many :readers
      has_many_to_many :alias_readers, class_name: :Reader
      has_many_to_many :books, class_name: "AModule::Book"
      has_many_to_many :libraries
      include Apiable
      api_writer :books, :readers, :libraries
      validates_presence_of :name
    end
  end

  class Reader < ActiveRecord::Base
    has_many_to_many :books, class_name: AModule::Book
    has_many_to_many :readers
    has_many_to_many :libraries
    include Apiable
    api_writer :books, :readers, :libraries
    validates_presence_of :name
  end

  class Library < ActiveRecord::Base
    has_many_to_many :books, class_name: AModule::Book
    has_many_to_many :readers
    include Apiable
    api_writer :books, :readers
    validates_presence_of :name
  end

  def create_temp_table(table_name, fields)
    m = ActiveRecord::Migration
    m.verbose = false
    begin
      m.drop_table table_name
    rescue
    end
    m.create_table table_name do |t|
      fields.each do |f, type|
        t.send(type, f)
      end
    end
    @temp_tables = [] if @temp_tables.nil?
    @temp_tables << table_name
  end

  def delete_temp_tables
    if @temp_tables
      m = ActiveRecord::Migration
      m.verbose = false
      @temp_tables.each { |table_name| m.drop_table table_name }
    end
  end

  describe :global_object_links do
    before :all do
      create_temp_table("books", { name: :string })
      create_temp_table("readers", { name: :string })
      create_temp_table("libraries", { name: :string })
    end

    after :all do
      delete_temp_tables
    end

    def book
      AModule::Book.new.tap { |obj| obj.name = obj.class.name }
    end

    def reader
      Reader.new.tap { |obj| obj.name = obj.class.name }
    end

    def library
      Library.new.tap { |obj| obj.name = obj.class.name }
    end

    def featured_item(feature, subject_namespace)
      case feature
      when ""
        library
      when "namespaced"
        book
      when "same type"
        subject_namespace.present? ? book : reader
      end
    end

    def prepare_test(subject_namespace, subject_state, feature, linked_state)
      @subject = (subject_namespace.present? ? book : reader)
      @subject.save! if subject_state == :existing
      @linked1 = featured_item(feature, subject_namespace)
      @linked2 = featured_item(feature, subject_namespace)
      @linked1.save! && @linked2.save! if linked_state == :existing
    end

    ["", "namespaced"].each do |subject_namespace|
      [:new, :existing].each do |subject_state|
        ["", "namespaced", "same type"].each do |feature|
          [:new, :existing].each do |linked_state|
            context "#{subject_state} #{subject_namespace} items linked to #{linked_state} #{feature} items".gsub(/\s+/, " ") do
              it "should be saved with the linked item" do
                prepare_test(subject_namespace, subject_state, feature, linked_state)

                @subject.send("#{@linked1.class.name.demodulize.underscore.pluralize}=", [@linked1, @linked2])
                @subject.save! if subject_state == :new
                expect(@linked1.send(@subject.class.name.demodulize.underscore.pluralize).size).to eq(1)
                expect(@linked2.send(@subject.class.name.demodulize.underscore.pluralize).size).to eq(1)
              end

              if linked_state == :existing
                it "should link using object ids" do
                  prepare_test(subject_namespace, subject_state, feature, linked_state)
                  @subject.send("#{@linked1.class.name.demodulize.underscore}_ids=", [@linked1.id, @linked2.id])
                  @subject.save!
                  expect(@linked1.send(@subject.class.name.demodulize.underscore.pluralize).size).to eq(1)
                  expect(@linked2.send(@subject.class.name.demodulize.underscore.pluralize).size).to eq(1)
                end
              end

              it "should raise en exception when setting two identical links" do
                prepare_test(subject_namespace, subject_state, feature, linked_state)
                if subject_state == :new
                  @subject.send("#{@linked1.class.name.demodulize.underscore.pluralize}=", [@linked1, @linked1])
                  expect { @subject.save! }.to raise_exception(ActiveRecord::RecordNotUnique)
                else
                  expect { @subject.send("#{@linked1.class.name.demodulize.underscore.pluralize}=", [@linked1, @linked1]) }.
                    to raise_exception(ActiveRecord::RecordNotUnique)
                end
              end

              it "should delete links for both sides" do
                prepare_test(subject_namespace, subject_state, feature, linked_state)
                @subject.send("#{@linked1.class.name.demodulize.underscore.pluralize}=", [@linked1, @linked2])
                @subject.save!
                @subject.send("#{@linked1.class.name.demodulize.underscore.pluralize}").clear
                expect(@linked1.send(@subject.class.name.demodulize.underscore.pluralize).size).to be_zero
                expect(@linked2.send(@subject.class.name.demodulize.underscore.pluralize).size).to be_zero
                expect(@subject.send("#{@linked1.class.name.demodulize.underscore.pluralize}").size).to be_zero
              end

              it "should delete object links with the object" do
                prepare_test(subject_namespace, subject_state, feature, linked_state)
                @subject.send("#{@linked1.class.name.demodulize.underscore.pluralize}=", [@linked1, @linked2])
                @subject.save!
                @subject.destroy
                case @linked1
                when AModule::Book
                  expect(@linked1.book_reader_links).to be_blank
                  expect(@linked1.book_library_links).to be_blank
                  expect(@linked1.book_book_links).to be_blank
                when Library
                  expect(@linked1.library_reader_links).to be_blank
                  expect(@linked1.book_library_links).to be_blank
                when Reader
                  expect(@linked1.book_reader_links).to be_blank
                  expect(@linked1.library_reader_links).to be_blank
                  expect(@linked1.reader_reader_links).to be_blank
                end
              end

              if subject_state == :new
                it "should't save a link to new object without save" do
                  prepare_test(subject_namespace, subject_state, feature, linked_state)
                  @subject.send("#{@linked1.class.name.demodulize.underscore.pluralize}=", [@linked1, @linked2])
                  expect(@linked1.send(@subject.class.name.demodulize.underscore.pluralize).size).to be_zero
                  expect(@linked2.send(@subject.class.name.demodulize.underscore.pluralize).size).to be_zero
                end

                it "should not save a link when save is failed, but preserve the link" do
                  prepare_test(subject_namespace, subject_state, feature, linked_state)
                  @subject.name = nil
                  @subject.send("#{@linked1.class.name.demodulize.underscore.pluralize}=", [@linked1, @linked2])
                  @subject.save
                  expect(@linked1.send(@subject.class.name.demodulize.underscore.pluralize).size).to be_zero
                  expect(@subject.send(@linked1.class.name.demodulize.underscore.pluralize).size).to eq(2)
                end
              end

              if subject_state == :existing && linked_state == :existing
                context "when using API" do
                  it "should link objects using object ids" do
                    prepare_test(subject_namespace, subject_state, feature, linked_state)
                    @subject.update_attributes!({ "#{@linked1.class.name.demodulize.underscore.pluralize}": [{ id: @linked1.id }] })
                    expect(@linked1.send(@subject.class.name.demodulize.underscore.pluralize).count).to eq(1)
                  end

                  it "should link objects using other attribute" do
                    prepare_test(subject_namespace, subject_state, feature, linked_state)
                    @linked1.update_attributes!(name: "test")
                    @subject.update_attributes!({ "#{@linked1.class.name.demodulize.underscore.pluralize}": [{ name: "test" }] })
                    expect(@linked1.send(@subject.class.name.demodulize.underscore.pluralize).count).to eq(1)
                  end
                end
              end
            end
          end
        end
      end
    end
  end

  class Floor < ActiveRecord::Base
    has_many_to_one :rooms
  end

  class Room < ActiveRecord::Base
    has_one_to_many :floors
  end

  def prepare_has_one_test(room_state, floor_state)
    @floor1 = Floor.new
    @floor1.save! if floor_state == :existing
    @floor2 = Floor.create!
    @room1 = Room.new
    @room1.save! if room_state == :existing
    @room2 = Room.create!
  end

  describe "has_one_to_many" do # check decleration order!!! missing single items methods!!!
    before :all do
      create_temp_table("floors", { name: :string })
      create_temp_table("rooms", { name: :string })
    end

    after :all do
      delete_temp_tables
    end

    [:new, :existing].each do |room_state|
      [:new, :existing].each do |floor_state|
        context "from the one side [#{room_state} one side, #{floor_state} many side]" do
          it "should save single item" do
            prepare_has_one_test(room_state, floor_state)
            @room1.floor = @floor1
            @room1.save! if @room1.new_record?
            expect(@room1.floor).to be_present
            expect(@room1.floors.count).to eq(1)
            expect(@floor1.rooms.count).to eq(1)
          end

          if floor_state == :existing
            it "should save single item id" do
              prepare_has_one_test(room_state, floor_state)
              @room1.floor_id = @floor1.id
              @room1.save! if @room1.new_record?
              expect(@room1.floor_id).to be_present
              expect(@room1.floors.count).to eq(1)
              expect(@floor1.rooms.count).to eq(1)
            end
          end

          # Notice: There is a bug in Rails that somehow, when setting on new record, one
          # associated new_record, and then persisted record, both are saved!
          # In this rare scenario the test fails, so here they are under condition that
          # the test do not run if the records are :new records, until it will be fixed.
          # This is very rare scenario, and currently in our application scenarios it cannot be happen.
          unless room_state == :new && floor_state == :new
            it "should replace single item" do
              prepare_has_one_test(room_state, floor_state)
              @room1.floors = [@floor1]
              @room1.floors = [@floor2]
              @room1.save! if @room1.new_record?

              expect(@room1.floors.count).to eq(1)
              expect(@room1.floors[0].id).to eq(@floor2.id)
              expect(@floor1.rooms.count).to eq(0)
              expect(@floor2.rooms.count).to eq(1)
            end

            it "should replace single item_id" do
              prepare_has_one_test(room_state, floor_state)
              @room1.floors = [@floor1]
              @room1.floor_ids = [@floor2.id]
              @room1.save! if @room1.new_record?

              expect(@room1.floors.count).to eq(1)
              expect(@room1.floors[0].id).to eq(@floor2.id)
              expect(@floor1.rooms.count).to eq(0)
              expect(@floor2.rooms.count).to eq(1)
            end
          end

          it "should add single item to existing other side multiple items" do
            prepare_has_one_test(room_state, floor_state)
            @floor1.rooms = [@room1]
            @room2.floors = [@floor1]
            expect(@room1.floors.count).to eq(1)
            expect(@floor1.rooms.count).to eq(2)
          end

          it "should save single item_id" do
            prepare_has_one_test(room_state, floor_state)
            @floor1.save! if @floor1.new_record?
            @room1.floor_ids = [@floor1.id]
            @room1.save! if @room1.new_record?
            expect(@room1.floor_id).to be_present
            expect(@room1.floors.count).to eq(1)
            expect(@floor1.rooms.count).to eq(1)
          end

          it "should add first item" do
            prepare_has_one_test(room_state, floor_state)
            @room1.floors << @floor1
            @room1.save! if @room1.new_record?
            expect(@floor1.rooms.count).to eq(1)
          end

          it "should create first item" do
            prepare_has_one_test(room_state, floor_state)
            @room1.save! if @room1.new_record?
            @new_floor = @room1.floors.create!
            expect(@new_floor.rooms.count).to eq(1)
          end

          it "should raise exception when saving multiple items" do
            prepare_has_one_test(room_state, floor_state)
            expect { @room1.floors = [@floor1, @floor2] }.to raise_exception(ActiveRecord::RecordNotUnique)
          end

          it "should raise exception when saving multiple item ids" do
            prepare_has_one_test(room_state, floor_state)
            @floor1.save! if @floor1.new_record?
            expect { @room1.floor_ids = [@floor1.id, @floor2.id] }.to raise_exception(ActiveRecord::RecordNotUnique)
          end

          it "should raise exception when pushing second item" do
            prepare_has_one_test(room_state, floor_state)
            @room1.floors = [@floor1]
            expect { @room1.floors << @floor2 }.to raise_exception(ActiveRecord::RecordNotUnique)
          end

          it "should raise exception when creating second item" do
            prepare_has_one_test(room_state, floor_state)
            @room1.floors = [@floor1]
            @room1.save! if @room1.new_record?
            expect { @room1.floors.create }.to raise_exception(ActiveRecord::RecordNotUnique)
          end

          it "should raise exception when creating! second item" do
            prepare_has_one_test(room_state, floor_state)
            @room1.floors = [@floor1]
            @room1.save! if @room1.new_record?
            expect { @room1.floors.create! }.to raise_exception(ActiveRecord::RecordNotUnique)
          end
        end

        context "from the many side [#{room_state} one side, #{floor_state} many side]" do
          it "should save multiple items" do
            prepare_has_one_test(room_state, floor_state)
            @floor1.rooms = [@room1, @room2]
            @floor1.save! if @floor1.new_record?
            expect(@room1.floors.count).to eq(1)
            expect(@floor1.rooms.count).to eq(2)
          end

          it "should run over existing item on saving items" do
            prepare_has_one_test(room_state, floor_state)
            @room1.floors = [@floor1]
            @floor2.rooms = [@room1, @room2]
            @room1.reload
            expect(@room1.floors.count).to eq(1)
            expect(@room1.floors[0].id).to eq(@floor2.id)
          end

          it "should run over existing item on saving item ids" do
            prepare_has_one_test(room_state, floor_state)
            @room1.floors = [@floor1]
            @room1.save! if @room1.new_record?
            @floor2.room_ids = [@room1.id, @room2.id]
            @room1.reload
            expect(@room1.floors.count).to eq(1)
            expect(@room1.floors[0].id).to eq(@floor2.id)
          end

          it "should run over existing same-item on saving items" do
            prepare_has_one_test(room_state, floor_state)
            @room1.floors = [@floor1]
            @room1.save! if @room1.new_record?
            @floor1.rooms = [@room1, @room2]
            @room1, @room2 = @floor1.rooms
            expect(@room1.floors.count).to eq(1)
            expect(@room2.floors.count).to eq(1)
          end

          it "should run over existing item on pushing items" do
            prepare_has_one_test(room_state, floor_state)
            @room1.floors = [@floor1]
            @floor2.rooms << [@room1, @room2]
            @room1.reload
            expect(@room1.floors.count).to eq(1)
            expect(@room1.floors[0].id).to eq(@floor2.id)
          end

          it "should raise exception when saving the same object twice" do
            prepare_has_one_test(room_state, floor_state)
            expect { @floor1.rooms = [@room1, @room1]; @floor1.save! if @floor1.new_record?}.to raise_exception(ActiveRecord::RecordNotUnique)
          end
        end
      end
    end
  end
end
