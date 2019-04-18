# # # # # # # # # # #
#  This script creates file with
#  names of all other files in given directory
# # # # # # # # # # #
#
#
def create_list(directory)
  require 'json'
  x = Dir.pwd.split'/'
  x.push("#{directory}")
  x = x.join'/'
  Dir.chdir x
  ffi = Dir.glob("*")
  f = File.new("A-Z_FILES_LIST", 'w')
  f << ffi.to_json
end

create_list 'TP'