require 'exifr/jpeg'

class Photo

  attr_accessor :id, :location
  attr_writer :contents

  class << self
    def mongo_client
      Mongoid::Clients.default
    end

    def all(offset=0, limit=0)
      mongo_client.database.fs.find.skip(offset).limit(limit).map do |doc|
        Photo.new(doc)
      end
    end

    def find(id)
      doc = mongo_client.database.fs.find(_id: BSON::ObjectId.from_string(id)).first

      doc ? Photo.new(doc) : nil
    end
  end

  def initialize(params=nil)
    if params
      @id = params[:_id].to_s if params[:_id]
      @location = Point.new(params[:metadata][:location]) if params[:metadata][:location]
    end
  end

  def persisted?
    !@id.nil?
  end

  def save
    unless persisted?
      @contents.rewind
      gps = EXIFR::JPEG.new(@contents).gps
      @location = Point.new(lng: gps.longitude, lat: gps.latitude)

      description = { 
        content_type: 'image/jpeg',
      }

      description[:metadata] = { location: @location.to_hash }

      @contents.rewind

      grid_file = Mongo::Grid::File.new(@contents.read, description)

      @id = self.class.mongo_client.database.fs.insert_one(grid_file).to_s

      @id
    end
  end

  def contents
    grid_file = self.class.mongo_client.database.fs.find_one(_id: BSON::ObjectId.from_string(id))
    tmp = ''

    grid_file.chunks.each do |chunk|
      tmp << chunk.data.data
    end

    tmp
  end

  def destroy
    self.class.mongo_client.database.fs.find(_id: BSON::ObjectId.from_string(id)).delete_one
  end

  private
    def find_nearest_place_id(max_distance)
      Place.near(location, max_distance)
    end
end