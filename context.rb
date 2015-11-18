#!/usr/bin/ruby

require 'active_record'
require 'securerandom'

ActiveRecord::Base.establish_connection(
	adapter: 'postgresql',
	host: 'database.orion.org',
	database: 'nco-devel',
	username: 'abramov',
	password: 'abramov')

module RESTCombine
	class InvalidRequest < StandardError
		attr_reader :code
		def initialize(msg, ret_code)
			super(msg)
			@code = ret_code
		end
	end
	module Entity
		def getList(params)
			rv = String.new
			ser_params = Hash.new
			if params.include? 'fields'
				ser_params[:only] = params['fields'].split(',')
				params.delete('fields')
			end
			json = JSON::GenericObject
			rv = where(params).to_json(ser_params)
			return rv
		end
		def read(uuid)
			begin
				return find(uuid).to_json
			rescue ActiveRecord::RecordNotFound
				raise InvalidRequest.new("#{Class.name} with uuid: #{uuid} not found.", 400)
			end
		end
		def append(json, uuid=nil)
			rec = new.from_json(json)
			uuid = SecureRandom.uuid if uuid.nil?
			rec.id = uuid
			rec.save
			return "{\"id\":\"#{rec.id}\"}"
		end
		def remove(uuid)
			rec = find(uuid)
			id = rec.id
			rec.destroy
			return "{\"id\":\"#{id}\"}"
		end
		def write(uuid, json)
			begin
				rec = find(uuid)
			rescue ActiveRecord::RecordNotFound
				return append(json, uuid)
			else
				rec.from_json(json)
				rec.save
				return "{\"id\":\"#{rec.id}\"}"
			end
		end
	end
	module Application
		def call(env)
			req = Rack::Request.new(env)
			params = Rack::Utils.parse_nested_query(req.query_string)
			uuidPat= "[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}"

			if req.get?
				case req.path_info
				when /^\/[A-Za-z]+s$/
					entity = req.path_info.reverse.chop.reverse.chop
					res = getEntity(entity).getList(params)
				when /^\/[A-Za-z]+\/#{uuidPat}$/
					entity = req.path_info.split('/')[1]
					uuid = req.path_info.split('/')[2]
					res = getEntity(entity).read(uuid)
				end
				return [200, {"Content-type"=>"text/plain;charset=UTF-8"}, [res]]
			elsif req.post?
				raise InvalidRequest.new("Invalid type", 400) if req.media_type != 'application/json'
				case req.path_info
				when /^\/[A-Za-z]+$/
					res = getEntity(req.path_info.split('/')[1]).append(req.body.read)
				end
				return [201, {"Content-type"=>"text/plain;charset=UTF-8"}, [res]]
			elsif req.delete?
				case req.path_info
				when /^\/[A-Za-z]+\/#{uuidPat}$/
					entity = req.path_info.split('/')[1]
					uuid = req.path_info.split('/')[2]
					res = getEntity(entity).remove(uuid)
				end
				return [200, {"Content-type"=>"text/plain;charset=UTF-8"}, [res]]
			elsif req.put?
				case req.path_info
					when /^\/[A-Za-z]+\/#{uuidPat}$/
					entity = req.path_info.split('/')[1]
					uuid = req.path_info.split('/')[2]
					begin
						res = getEntity(entity).write(uuid, req.body.read)
					end
				end
				return [200, {"Content-type"=>"text/plain;charset=UTF-8"}, [res]]
			end
			rescue RESTCombine::InvalidRequest => ie
				return [ie.code, {"Content-type"=>"text/plain;charset=UTF-8"}, [ie.message]]
			rescue ActiveRecord::ActiveRecordError => err
				return [400, {"Content-type"=>"text/plain;charset=UTF-8"}, ["#{err.class.name}: #{err.message}"]]
			rescue JSON::ParserError => err
				return [400, {"Content-type"=>"text/plain;charset=UTF-8"}, ["#{err.class.name}: #{err.message}"]]
			end
			return [400, {"Content-type"=>"text/plain;charset=UTF-8"}, ["Invalid request."]]
		end
		private
		def getEntity(name)
			begin
				return  Object.const_get(name)
			rescue NameError
				raise InvalidRequest.new("Invalid entity name: #{name}", 404)
			end
		end
	end
end

# Аэродромы не работают в связи с наличием поля "class" в таблице БД.
class Runway < ActiveRecord::Base
	extend RESTCombine::Entity
	self.table_name = 's_ani.runway'		# переменные ананимного класса
end

class AniApp
	include RESTCombine::Application
end
