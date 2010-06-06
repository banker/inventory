require 'rubygems'
require 'mongo'

class InventoryFetchFailure < StandardError
end

module InventoryState
  AVAILABLE = 0
  CART      = 1
  PRE_ORDER = 2
  PURCHASED = 3
end

class InventoryFetcher
  include InventoryState

  def initialize(opts={})
    @orders    = opts[:orders]
    @inventory = opts[:inventory]
  end

  def add_to_cart(order_id, *items)
    item_selectors = []
    items.each do |item|
      item[:qty].times do
        item_selectors << {:sku => item[:sku]}
      end
    end

    transition_state(order_id, item_selectors, :from => AVAILABLE, :to => CART)
  end

  private

  # NOTE: Need to fix the coupling of the operation on @orders here.
  #
  # @return [Integer] number of items transitioned
  def transition_state(order_id, selectors, opts={})
    items_transitioned = []

    begin
      for selector in selectors do
        selector.merge(:state => opts[:from])
        item_id = fetch_item(selector, :from => opts[:from], :to => opts[:to])
        items_transitioned << item_id
        @orders.update({:_id => order_id}, {"$push" => {:item_ids => item_id}})
      end

    rescue Mongo::OperationFailure
      rollback(order_id, items_transitioned, opts[:from], opts[:to])
      raise InventoryFetchFailure
    end

    items_transitioned.size
  end

  # Fetch an item matching a given selector, and advance its
  # state as determined by opts[:from] and opts[:to].
  #
  # @raise [Mongo::OperationFailure] if the find_and_modify operation fails
  #
  # @return [BSON::ObjectID] the _id of the physical
  #   inventory item returned
  def fetch_item(item_selector, opts)
    query = item_selector.merge({:state => opts[:from]})
    physical_item = @inventory.find_and_modify(:query => query,
      :update => {'$set' => {:state => opts[:to], :add_time => Time.now}})

    physical_item['_id']
  end

  # Take a list of items added to an order, remove them, and
  # the mark them as available.
  def rollback(order_id, item_ids, old_state, new_state)
    @orders.update({"_id" => order_id}, {"$pullAll" => {:item_ids => item_ids}})

    item_ids.each do |id|
      @inventory.find_and_modify(:query => {"_id" => id, :state => new_state},
        :update => {"$set" => {:state => old_state, :add_time => nil}})
    end
  end

end
