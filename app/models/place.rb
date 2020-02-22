class Place
  attr_accessor :id, :formatted_address, :location, :address_components

  class << self
    def mongo_client
      Mongoid::Clients.default
    end

    def collection
      mongo_client[:places]
    end

    def load_all(file)
      array = JSON.parse(file.read)
      collection.insert_many(array)
    end

    def find_by_short_name(input_string)
      collection.find("address_components.short_name": input_string)
    end

    def to_places(mongo_collection)
      results = []
      mongo_collection.each do | p |
        results << Place.new(p)
      end

      results
    end

    def find(id)
      id = BSON::ObjectId.from_string(id)
      result = collection.find(_id: id).first

      result = Place.new(result) if result 

      result
    end

    def all(offset=0, limit=0)
      places = []
      collection.find.skip(offset).limit(limit).each do |doc|
        places << Place.new(doc)
      end

      places
    end

    def get_address_components(sort={}, offset=0, limit=nil)
      q = []
      q << {:$unwind => '$address_components'}
      q << {:$project => { _id: 1, address_components: 1, formatted_address: 1, 'geometry.geolocation': 1}}
      q << {:$sort => sort } if !sort.empty?      
      q << {:$skip => offset}
      q << {:$limit => limit} if !limit.nil?      

      collection.find.aggregate(q)
    end

    def get_country_names
      result = collection.find.aggregate([
        {:$unwind => '$address_components' },
        {:$project => { 'address_components.long_name': 1, 'address_components.types': 1 }},
        {:$match => { 'address_components.types': "country" }},
        {:$group => { _id: '$address_components.long_name' }}
      ]).to_a

      countries = result.map { |h| h[:_id] }
    end

    def find_ids_by_country_code(country_code)
     collection.find.aggregate([
        { :$match => { :$and => [ 
                                 { 'address_components.types': "country" },
                                 { 'address_components.short_name': country_code }
                                ] 
                      }
        },

        { :$project => { _id: 1 } }
      ]).to_a.map { |h| h[:_id].to_s }
    end

    def create_indexes
      collection.indexes.create_one(
       { 'geometry.geolocation': Mongo::Index::GEO2DSPHERE }
      )
    end

    def remove_indexes
      collection.indexes.drop_one('geometry.geolocation_2dsphere')
    end

    def near(point, max_meters=0)
      point = point.to_hash

      collection.find(
        'geometry.geolocation': {
          :$near => {
            :$geometry => point,
            :$maxDistance => max_meters
          }
        }
      )
    end
  end

  def initialize(params)
    @id = params[:_id].to_s
    @address_components = params[:address_components]
    @formatted_address = params[:formatted_address]
    @location = Point.new(params[:geometry][:geolocation])
    @address_components = []

    if params[:address_components]
      params[:address_components].each do |address_component|
        @address_components << AddressComponent.new(address_component)
      end
    end
  end

  def destroy
    bson_id = BSON::ObjectId.from_string(id)
    self.class.collection.find(_id: bson_id).delete_one
  end

  def near(max_meters=0)
    docs = self.class.near(self.location, max_meters)
    places = self.class.to_places(docs)

    places
  end
end