class Branch
  extend Reporting::BranchReports
  include DataMapper::Resource

  before :save, :convert_blank_to_nil
  
  property :id,      Serial
  property :name,    String, :length => 100, :nullable => false, :index => true
  property :code,    String, :length => 10, :nullable => true, :index => true, :min => 1, :max => 10
  property :address, Text,   :lazy => true
  property :contact_number, String, :length => 40, :lazy => true
  property :landmark,       String, :length => 100, :lazy => true  
  property :created_at,     DateTime
  property :creation_date,  Date, :default => Date.today
  property :area_id,        Integer, :nullable => true
  belongs_to :manager,      :child_key => [:manager_staff_id], :model => 'StaffMember'
  belongs_to :area,         :nullable => true
  has n, :centers
  has n, :audit_trails, :auditable_type => "Branch", :child_key => ["auditable_id"]

  validates_is_unique   :code
  validates_length      :code, :min => 1, :max => 10

  validates_length      :name, :min => 3
  validates_present     :manager
  validates_with_method :manager, :method => :manager_is_an_active_staff_member?

  def self.from_csv(row, headers)
    obj = new(:code => row[headers[:code]], :name => row[headers[:name]], :address => row[headers[:address]], 
              :manager => StaffMember.first(:name => row[headers[:manager]]))
    [obj.save, obj]
  end

  def centers_with_paginate(params, user)
    hash = {:order => [:meeting_day, :meeting_time_hours, :meeting_time_minutes]}
    # This the logged in person is a staff member and he is not a branch manager
    if staff = user.staff_member and not staff==self.manager
      if not staff.branches.include?(self) and not staff.areas.branches.include?(self) and not staff.regions.areas.branches.include?(self)
        hash[:manager] = user.staff_member
      end
    elsif user.role == :funder and funding_lines = Funder.first(:user_id => user.id).funding_lines
      hash[:id] = LoanHistory.parents_where_loans_of(Center, {:loan => {:funding_line_id => funding_lines.map{|x| x.id}}})
    end
    hash[:branch] = self    

    if params[:meeting_day] and Center::DAYS.include?(params[:meeting_day].to_sym)
      hash[:meeting_day]= params[:meeting_day].to_sym
    else
      hash[:meeting_day]=Date.today.weekday
    end

    Center.all(hash)
  end

  def client_groups(hash={})
    self.centers.client_groups(hash)
  end

  def clients(hash={})
    self.centers.clients(hash)
  end

  def loans(hash={})
    self.centers.clients.loans(hash)
  end

  def self.search(q)
    if /^\d+$/.match(q)
      Branch.all(:conditions => {:id => q})
    else
      Branch.all(:conditions => ["code=? or name like ?", q, q+'%'])
    end
  end
  
  def client_ids
    repository.adapter.query(%Q{
                                SELECT cl.id clid
                                FROM branches b, centers c, clients cl
                                WHERE b.id=#{self.id} AND b.id=c.branch_id AND c.id=cl.center_id AND cl.deleted_at is NULL
                             })    
  end

  private
  def manager_is_an_active_staff_member?
    return true if manager and manager.active
    [false, "Managing staff member is currently not active"]
  end

  def convert_blank_to_nil
    self.attributes.each{|k, v|
      if v.is_a?(String) and v.empty? and self.class.send(k).type==Integer
        self.send("#{k}=", nil)
      end
    }
  end
end
