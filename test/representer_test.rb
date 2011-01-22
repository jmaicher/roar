require 'test_helper'
require "active_support/core_ext/class/attribute"
require "hooks/inheritable_attribute"

Collection = Roar::Representation::UnwrappedCollection
  
  # fixtures:  
  class TestModel
    include Roar::Representer::Xml
    
    extend Hooks::InheritableAttribute
    # TODO: Move to Representer::Xml
    inheritable_attr :xml_collections
    self.xml_collections = {}
    
    
    attr_accessor :attributes
    
    def self.model_name
      "test"
    end
    
    def initialize(attributes={})
      @attributes = attributes
    end
  end
  
  class Item < TestModel
    def to_xml(options); options[:builder].tag! :item, attributes; end
    def self.from_xml(xml); self.new Hash.from_xml(xml)["item"]; end
    def ==(b)
      attributes == b.attributes
    end
  end

class PublicXmlRepresenterAPITest < MiniTest::Spec
  describe "The public XML Representer API" do
    before do
      @c = Class.new(TestModel)
      @o = @c.new "name" => "Joe"
    end
    
    it "#attributes returns generic attributes hash" do
      assert_equal({"name" => "Joe"}, @o.attributes)
    end
    
    it "#attributes_for_xml returns attributes hash ready for xml rendering" do
      assert_equal({"name" => "Joe"}, @o.attributes_for_xml)
    end
    
    it "#to_xml renders XML as string" do
      assert_equal "<test>\n  <name>Joe</name>\n</test>\n", @o.to_xml
    end
    
    it ".from_xml creates model from xml" do
      assert_equal @o.attributes, @c.from_xml("<test>\n  <name>Joe</name>\n</test>\n").attributes
    end
    
    it ".from_attributes creates model from parsed XML attributes hash" do
      assert_equal @o.attributes, @c.from_xml_attributes("name" => "Joe").attributes
    end
    
    it ".from_attributes creates model from generic attributes hash" do
      assert_equal @o.attributes, @c.from_attributes("name" => "Joe").attributes
    end
    
    #it "#to_xml respects #attributes_for_xml" do
    #  @o.instance_eval do
    #    def attributes_for_xml(*) # user overrides it in the "representing" class.
    #      super.merge!({"kind" => "nice"})
    #    end
    #  end
    #  assert_equal "<TestModel>\n  <name>Joe</name>\n  <kind>nice</kind>\n</TestModel>\n", @o.to_xml
    #end
  end
end

class CollectionInRepresenterTest < MiniTest::Spec
  describe ".collection within .xml" do
    before do
      @c = Class.new(TestModel)
      assert_equal({}, @c.xml_collections)
    end
    
    it "sets the class attribute" do
      @c.xml do
        collection :items
      end
      
      assert_equal({:items => {}}, @c.xml_collections)
    end
    
    it "accepts options" do
      @c.xml do
        collection :items, :class => Item
      end
      
      assert_equal({:items => {:class => Item}}, @c.xml_collections)
    end
  end
  
  describe "A Model with mixed-in Roar::Representer::Xml" do
    before do
      @c = Class.new(TestModel)
      @l = @c.new "name" => "tucker", "items" => [{}, {}]
      
      @c.collection :items
    end
    
    describe "attributes defined as collection" do
      it "#to_xml doesn't wrap collection attributes" do
        assert_equal "<test>
  <name>tucker</name>
  <item>\n  </item>
  <item>\n  </item>
</test>\n", @l.to_xml(:skip_instruct=>true)  # FIXME: make standard/#as_xml
      end
    
      it ".from_xml pushes deserialized items to the pluralized attribute" do
        assert_equal @c.new("name" => "tucker", "items" => ["Beer", "Peanut Butter"]).attributes, @c.from_xml("<test>
  <name>tucker</name>
  <item>Beer</item>
  <item>Peanut Butter</item>
  </test>").attributes
      end
      
      it ".from_xml pushes one single deserialized item to the pluralized attribute" do
        assert_equal @c.new("name" => "tucker", "items" => ["Beer"]).attributes, @c.from_xml("<test>
    <name>tucker</name>
    <item>Beer</item>
  </test>").attributes
      end
    end
          
      it ".collection respects :class in .from_xml" do 
        @c.xml do
          collection :items, :class => Item  # in: calls Item.from_hash(<item>...</item>), +above. out: item.to_xml
        end
        
        @l = @c.from_xml("<test>
  <name>tucker</name>
  <item>beer</item>
  <item>chips</item>
</test>")

        assert_equal [Item.new("beer"), Item.new("chips")], @l.attributes["items"]
      end
      
  end
  
  
  describe "UnwrappedCollection" do
    before do
      @l = Collection.new([{:number => 1}, {:number => 2}])
      @xml = Builder::XmlMarkup.new
    end
    
    it "#to_xml returns contained items without a wrapping tag" do
      @l.to_xml(:builder => @xml)
      assert_equal "<?xml version=\"1.0\" encoding=\"UTF-8\"?><hash><number type=\"integer\">1</number></hash><?xml version=\"1.0\" encoding=\"UTF-8\"?><hash><number type=\"integer\">2</number></hash>", @xml.target!
    end
    
    it "#to_xml works with one single item" do
      Collection.new([{:number => 1}]).to_xml(:builder => @xml, :skip_instruct => true)
      assert_equal "<hash><number type=\"integer\">1</number></hash>", @xml.target!
    end
    
    it "#to_xml accepts options" do
      @l.to_xml(:builder => @xml, :skip_instruct => true, :skip_types => true)
      assert_equal "<hash><number>1</number></hash><hash><number>2</number></hash>", @xml.target!
    end
    
    it "#to_xml works in a nested hash" do
      assert_equal "<hash>
  <order>
    <position>
      <article>Peanut Butter</article>
      <amount>1</amount>
    </position>
    <position>
      <article>Hoepfner Pils</article>
      <amount>2</amount>
    </position>
  </order>\n</hash>\n", {:order => {:position => Collection.new([
{:article => "Peanut Butter", :amount => 1}, 
{:article => "Hoepfner Pils", :amount => 2}])}}.to_xml(:skip_instruct => true, :skip_types => true)
    end
    
    it "#to_xml works with contained objects that respond to #to_xml themselves" do
      class Method
        def initialize(verb) @verb = verb end
        def to_xml(o) o[:builder].tag!(:method, :type => @verb) end
      end
      
      @l = Collection.new([Method.new(:PUT), Method.new(:GET)])
      @l.to_xml(:builder => @xml)
      assert_equal "<method type=\"PUT\"/><method type=\"GET\"/>", @xml.target!
    end 
  end
  
  class TestItemTest < MiniTest::Spec
    before do
      @i = Item.new("Beer") 
    end
    
    it "responds to #to_xml" do
      assert_equal "<item>Beer</item>", @i.to_xml(:builder => Builder::XmlMarkup.new)
    end
    
    it "responds to #from_xml" do
      assert_equal @i.attributes, Item.from_xml("<item>Beer</item>").attributes
    end
    
    it "responds to #==" do
      assert_equal Item.new("Beer"), @i
      assert Item.new("Auslese") != @i
    end
  end
end
