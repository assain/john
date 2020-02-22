class Point
  attr_accessor :longitude, :latitude

  def initialize(params)
    if params.has_key?(:lat)
      @latitude = params[:lat]
      @longitude = params[:lng]
    else
      @longitude, @latitude = params[:coordinates]
    end
  end

  def to_hash
    { "type": "Point", "coordinates": [longitude, latitude] }
  end
end
