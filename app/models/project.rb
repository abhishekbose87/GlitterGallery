class Project < ActiveRecord::Base
  after_create :set_path, :init
  after_destroy :deletefiles

  belongs_to :user
  has_many :project_followers, dependent: :destroy,
                               foreign_key: 'project_id'
  has_many :followers, through: :project_followers,
                       class_name: 'User',
                       foreign_key: 'follower_id'
  has_many :issues

  validates :name, presence: true, uniqueness: { scope: :user }
  validates :user, presence: true

  # Returns a list of public projects that belong to other users.
  def self.inspiring_projects_for(user_id)
    Project.where.not(private: true, user_id: user_id)
  end

  def last_updated
    repo = barerepo
    repo.head.target.time
  end

  def deletefiles
    FileUtils.rm_rf path
  end

  def imageurl(imagename)
    File.join(satellitedir, imagename).gsub('public', '')
  end

  # Project URL
  def urlbase
    File.join("/#{user.username}",
              name.gsub(' ', '%20'),
              uniqueurl.to_s).gsub(/\/$/, '')
  end

  def issues_url
    File.join urlbase, 'issues'
  end

  def barerepo
    Rugged::Repository.new barerepopath
  end

  def satelliterepo
    Rugged::Repository.new satelliterepopath
  end

  def barerepopath
    File.join path , 'repo.git'
  end

  def satelliterepopath
    File.join path , 'satellite' , '.git'
  end

  def satellitedir
    File.join path , 'satellite'
  end

  # Push the existing contents of the satellite repo to the bare repo
  def pushtobare
    remote = satelliterepo.remotes['bare']
    remote = satelliterepo.remotes.create 'bare', barerepo.path unless remote
    satelliterepo.push remote, ['refs/heads/master']
  end

  private

  def set_path
    user = User.find user_id
    self.path = File.join Glitter::Application.config.repo_dir,
                          'repos', user.email.to_s, name
    logger.debug "setting path - path: #{path}"
    save
  end

  # Path: public/data/repos/user_id/project_id
  # Bare Repo Path: public/data/repos/user_id/project_id/repo.git
  # Satellite Repo Path: public/data/repos/user_id/project_id/satellite/.git
  def init
    logger.debug "Initing repo path: #{path}"
    return unless File.exists? path

    if parent.nil? || parent == id
      Rugged::Repository.init_at barerepopath, :bare
      Rugged::Repository.clone_at barerepopath, satelliterepopath
    else # it's a fork, therefore:
      parent = Project.find parent
      Rugged::Repository.init_at barerepopath, :bare
      Rugged::Repository.clone_at parent.satelliterepopath, satelliterepopath
    end
    pushtobare unless satelliterepo.empty?
  end

end
