require 'test/test_helper'

class InventoryTest < Test::Unit::TestCase

  $db = Mongo::Connection.new['inventory-test']

  def setup
    @inventory = $db['inventory']
    @orders    = $db['orders']

    @inventory.remove
    @orders.remove
  end

  # Nine balls, bats, and gloves (three of each) added to the
  # inventory collection. For simplicity's sake, we assume that
  # the sku is synonomous with the product name.
  def populate_inventory
    ['ball', 'bat', 'glove'].each do |item|
      3.times do
        @inventory.insert({:sku => item, :state => InventoryState::AVAILABLE})
      end
    end
  end

  context "An order with standard inventory:" do
    setup do
      @fetcher  = InventoryFetcher.new(:orders => @orders, :inventory => @inventory)
      @order_id = @orders.insert({:username => 'kbanker', :item_ids => []})
      populate_inventory
    end

    should "contain nine inventory items" do
      assert_equal 3, @inventory.find({:sku => "ball"}).count
      assert_equal 3, @inventory.find({:sku => "bat"}).count
      assert_equal 3, @inventory.find({:sku => "glove"}).count
    end

    context "when available items are added to cart" do
      setup do
        @fetcher.add_to_cart(@order_id, {:sku => "ball", :qty => 3},
                                        {:sku => "glove", :qty => 1})
      end

      should "add items to order" do
        order = @orders.find_one({"_id" => @order_id})
        assert_equal 4, order['item_ids'].length

        order['item_ids'].each do |item_id|
          item = @inventory.find_one({"_id" => item_id})
          assert_equal InventoryState::CART, item['state']
        end
      end

      should "fail to add unavailable items to cart" do
        assert_raise InventoryFetchFailure do
          @fetcher.add_to_cart(@order_id, {:sku => "ball", :qty => 1})
        end
      end
    end

    context "when an add_to_cart operation fails" do
      setup do
        assert_raise InventoryFetchFailure do
          @fetcher.add_to_cart(@order_id, {:sku => "ball", :qty => 5})
        end
      end

      should "add no items to the order" do
        order = @orders.find_one({"_id" => @order_id})
        assert_equal [], order["item_ids"]
      end

      should "leave all items in an available state" do
        assert_equal 9, @inventory.find({:state => InventoryState::AVAILABLE}).count
      end
    end
  end
end
