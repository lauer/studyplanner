require 'rubygems'
require_gem 'activerecord'
require 'defaultDriver'
require 'find'

BASEDIR = 'c:/htdocs/studyplanner'

Find.find("#{BASEDIR}/app/models") do |model|
  require model if FileTest.file?(model)
end

@dbs = YAML::load(ERB.new(IO.read("#{BASEDIR}/config/database.yml")).result)

# to slurp records into production db, change this line to production.
curr_db = @dbs["development"]

# these parameters are mysql-specific, figure out how to improve
ActiveRecord::Base.establish_connection(:adapter => curr_db["adapter"],
                                        :database => curr_db["database"],
                                        :host => curr_db["host"],
                                        :username => curr_db["username"],
                                        :password => curr_db["password"])


timetable_modules = TimetableModule.find :all
timetable_modules.map! do |ttm|
  case ttm.name
    when 'E3W' then ttm.name = 'January'
    when 'F3W' then ttm.name = 'June'
  end
  ttm    
end

def arrayize(obj)
  obj.is_a?(Array) ? obj : [obj]
end

driver = CourseSoap.new

results = driver.searchDtuShb(SearchDtuShb.new('', '', '2', '', '2006/2007','','','','FullXML','','','',''))

results.searchDtuShbResult.root.courses.each do |cXML|
  puts "-----  COURSE -----"
  courseXML = cXML.fullXML.course
  
  title = courseXML.title.find { |t| t.xmlattr_Lang == 'en-gb' }.xmlattr_Title
  code = courseXML.xmlattr_CourseCode
  points = courseXML.point
  
  begin
    objectives = courseXML.txt.find { |t| t.xmlattr_Lang == 'en-gb' }.course_Objectives
  rescue
#    puts courseXML.txt.inspect if courseXML.respond_to?(:txt)
    puts "#{title} [#{code}] has no English objectives!"
    objectives = "No description available."
  end
  
  begin
    contents = courseXML.txt.find { |t| t.xmlattr_Lang == 'en-gb' }.contents
  rescue
#    puts courseXML.txt.inspect if courseXML.respond_to?(:txt)
    puts "#{title} [#{code}] has no English contents!"
    contents = "No description available."
  end
  
  begin
    course = Course.create!(:name => title, :code => code, :points => points, :objectives => objectives, :contents => contents)
    
    valid = true
    
    if courseXML.respond_to?(:class_Schedule)
      arrayize(courseXML.class_Schedule).each do |group|
  #      puts ">"
        if group.respond_to?(:schedule)
          course_version = course.course_versions.create
          arrayize(group.schedule).each do |schedule|
          ttms = timetable_modules.select { |ttm| ttm.name.include?(schedule.xmlattr_ScheduleKey) }
            if ttms.length > 0
              ttms.each do |ttm|
                course_version.locations.create(:timetable_module => ttm)
                puts "\t#{ttm.name}"
              end
            else
              valid = false
              puts "\t#{schedule.xmlattr_ScheduleKey} not recognized"
            end
          end
        elsif group.respond_to?(:schedule_Txt)
          valid = false
          arrayize(group.schedule_Txt).each do |schedule|
            puts "\t#{schedule.xmlattr_Txt}"
          end
        else
          valid = false
          puts "\tCould not recognize schedules."
        end
  #      puts "<"
      end
    else
      valid = false
      puts "No class schedules found!"
    end
    
    if valid
      puts "#{title} [#{code}] successfully imported"
    else
      course.destroy
      puts "#{title} [#{code}] requires manual handling"
    end
    
    puts ""
  rescue
    puts "Import of #{title} [#{code}] failed: #{$!}"
    course.destroy if course
  end
  
end