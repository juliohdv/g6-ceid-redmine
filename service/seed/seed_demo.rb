# frozen_string_literal: true
# Seeder de verificación — un proyecto demo con datos mínimos para validar el modelo BI.
# Uso (desde el host):
#   docker cp service/seed/seed_demo.rb redmine:/tmp/seed_demo.rb
#   docker exec redmine bundle exec rails runner /tmp/seed_demo.rb RAILS_ENV=production
#
# Idempotente: si el proyecto "bi-demo" ya existe, no vuelve a crear datos.

IDENTIFIER = 'bi-demo'
PROJECT_NAME = 'BI Demo Portfolio'

admin = User.find_by!(login: 'admin')
User.current = admin

# --- Users (demo team) -------------------------------------------------------
def find_or_create_user(login, firstname, lastname)
  user = User.find_by(login: login)
  return user if user

  user = User.new(
    login: login,
    firstname: firstname,
    lastname: lastname,
    mail: "#{login}@example.com",
    language: 'en',
    status: User::STATUS_ACTIVE
  )
  user.password = 'Demo1234!'
  user.password_confirmation = 'Demo1234!'
  user.save!
  user
end

dev_alice = find_or_create_user('alice', 'Alice', 'Developer')
dev_bob   = find_or_create_user('bob', 'Bob', 'Developer')
mgr_carol = find_or_create_user('carol', 'Carol', 'Manager')

role_dev = Role.find_by!(name: 'Developer')
role_mgr = Role.find_by!(name: 'Manager')

# --- Project -----------------------------------------------------------------
project = Project.find_by(identifier: IDENTIFIER)
if project.nil?
  project = Project.new(
    name: PROJECT_NAME,
    identifier: IDENTIFIER,
    description: 'Proyecto seed para validar star schema / KPIs de Power BI.',
    is_public: true,
    status: Project::STATUS_ACTIVE
  )
  project.enabled_module_names = %w[issue_tracking time_tracking]
  project.save!
else
  puts "INFO: project '#{IDENTIFIER}' already exists (id=#{project.id}); continuing seed if empty."
end

if project.issues.exists?
  puts "SKIP: project '#{IDENTIFIER}' already has #{project.issues.count} issues."
  exit 0
end

# Memberships (ignore if already present)
[[mgr_carol, role_mgr], [dev_alice, role_dev], [dev_bob, role_dev], [admin, role_mgr]].each do |user, role|
  member = Member.find_or_initialize_by(project: project, user: user)
  member.roles << role unless member.roles.include?(role)
  member.save!
end

# --- Versions (keep open while assigning issues; close Sprint 1 at the end) --
sprint1 = Version.find_or_create_by!(project: project, name: 'Sprint 1') do |v|
  v.description = 'Primer sprint demo'
  v.effective_date = Date.today - 7
  v.status = 'open'
  v.sharing = 'none'
end
sprint1.update!(status: 'open', effective_date: Date.today - 7)

sprint2 = Version.find_or_create_by!(project: project, name: 'Sprint 2') do |v|
  v.description = 'Sprint en curso'
  v.effective_date = Date.today + 7
  v.status = 'open'
  v.sharing = 'none'
end
sprint2.update!(status: 'open', effective_date: Date.today + 7)

# --- Reference lookups -------------------------------------------------------
status_new        = IssueStatus.find_by!(name: 'New')
status_progress   = IssueStatus.find_by!(name: 'In Progress')
status_resolved   = IssueStatus.find_by!(name: 'Resolved')
status_closed     = IssueStatus.find_by!(name: 'Closed')

tracker_bug       = Tracker.find_by!(name: 'Bug')
tracker_feature   = Tracker.find_by!(name: 'Feature')
tracker_support   = Tracker.find_by!(name: 'Support')

priority_low      = IssuePriority.find_by!(name: 'Low')
priority_normal   = IssuePriority.find_by!(name: 'Normal')
priority_high     = IssuePriority.find_by!(name: 'High')
priority_urgent   = IssuePriority.find_by!(name: 'Urgent')

activity_dev      = TimeEntryActivity.find_by!(name: 'Development')
activity_design   = TimeEntryActivity.find_by!(name: 'Design')

# Trackers must be enabled on the project
project.trackers = [tracker_bug, tracker_feature, tracker_support]
project.save!

# --- Issues ------------------------------------------------------------------
# Spec: subject, tracker, status, priority, assignee, version, estimated,
#       start_date, due_date, done_ratio, closed? (via status)
issue_specs = [
  {
    subject: 'Setup CI pipeline',
    tracker: tracker_feature,
    status: status_closed,
    priority: priority_normal,
    assigned_to: dev_alice,
    version: sprint1,
    estimated_hours: 8.0,
    start_date: Date.today - 20,
    due_date: Date.today - 14,
    done_ratio: 100,
    hours: [[dev_alice, 6.0, Date.today - 16, activity_dev],
            [dev_alice, 3.0, Date.today - 15, activity_dev]]
  },
  {
    subject: 'Login page redesign',
    tracker: tracker_feature,
    status: status_closed,
    priority: priority_high,
    assigned_to: dev_bob,
    version: sprint1,
    estimated_hours: 12.0,
    start_date: Date.today - 18,
    due_date: Date.today - 10,
    done_ratio: 100,
    hours: [[dev_bob, 5.0, Date.today - 14, activity_design],
            [dev_bob, 8.0, Date.today - 12, activity_dev]]
  },
  {
    subject: 'Fix null pointer on export',
    tracker: tracker_bug,
    status: status_closed,
    priority: priority_urgent,
    assigned_to: dev_alice,
    version: sprint1,
    estimated_hours: 4.0,
    start_date: Date.today - 12,
    due_date: Date.today - 9,
    done_ratio: 100,
    hours: [[dev_alice, 5.5, Date.today - 10, activity_dev]]
  },
  {
    subject: 'API rate limiting',
    tracker: tracker_feature,
    status: status_progress,
    priority: priority_high,
    assigned_to: dev_alice,
    version: sprint2,
    estimated_hours: 16.0,
    start_date: Date.today - 3,
    due_date: Date.today + 4,
    done_ratio: 40,
    hours: [[dev_alice, 4.0, Date.today - 2, activity_dev],
            [dev_alice, 3.0, Date.today - 1, activity_dev]]
  },
  {
    subject: 'Dashboard empty state',
    tracker: tracker_feature,
    status: status_progress,
    priority: priority_normal,
    assigned_to: dev_bob,
    version: sprint2,
    estimated_hours: 6.0,
    start_date: Date.today - 2,
    due_date: Date.today + 5,
    done_ratio: 25,
    hours: [[dev_bob, 2.0, Date.today - 1, activity_design]]
  },
  {
    subject: 'Slow query on issues list',
    tracker: tracker_bug,
    status: status_new,
    priority: priority_high,
    assigned_to: dev_bob,
    version: sprint2,
    estimated_hours: 8.0,
    start_date: Date.today,
    due_date: Date.today + 6,
    done_ratio: 0,
    hours: []
  },
  {
    subject: 'Onboard new contractor',
    tracker: tracker_support,
    status: status_resolved,
    priority: priority_low,
    assigned_to: mgr_carol,
    version: sprint2,
    estimated_hours: 2.0,
    start_date: Date.today - 5,
    due_date: Date.today - 1,
    done_ratio: 90,
    hours: [[mgr_carol, 1.5, Date.today - 3, activity_dev]]
  },
  {
    subject: 'Unassigned backlog item',
    tracker: tracker_feature,
    status: status_new,
    priority: priority_low,
    assigned_to: nil,
    version: nil,
    estimated_hours: 3.0,
    start_date: nil,
    due_date: nil,
    done_ratio: 0,
    hours: []
  }
]

created_issues = []

issue_specs.each do |spec|
  issue = Issue.new(
    project: project,
    tracker: spec[:tracker],
    author: admin,
    subject: spec[:subject],
    description: "Seed issue: #{spec[:subject]}",
    status: spec[:status],
    priority: spec[:priority],
    assigned_to: spec[:assigned_to],
    fixed_version: spec[:version],
    estimated_hours: spec[:estimated_hours],
    start_date: spec[:start_date],
    due_date: spec[:due_date],
    done_ratio: spec[:done_ratio]
  )
  issue.save!
  created_issues << issue

  # Time entries linked to the issue
  spec[:hours].each do |user, hours, spent_on, activity|
    TimeEntry.create!(
      project: project,
      issue: issue,
      user: user,
      hours: hours,
      spent_on: spent_on,
      activity: activity,
      comments: "Seed time for #{spec[:subject]}"
    )
  end
end

# Project-level time entry without issue (edge case for BI)
TimeEntry.create!(
  project: project,
  issue: nil,
  user: mgr_carol,
  hours: 1.0,
  spent_on: Date.today - 4,
  activity: activity_dev,
  comments: 'Planning meeting (no issue)'
)

# Force closed_on for closed issues if Redmine did not set it via callbacks
created_issues.select { |i| i.status.is_closed? }.each do |issue|
  if issue.closed_on.nil?
    issue.update_column(:closed_on, (issue.due_date || Date.today) + 1)
  end
end

# Close Sprint 1 after issues are assigned (Redmine blocks assigning closed versions)
sprint1.reload
sprint1.update!(status: 'closed')

puts 'OK: demo seed applied'
puts "  project:     #{project.identifier} (id=#{project.id})"
puts "  versions:    #{project.versions.count}"
puts "  members:     #{project.members.count}"
puts "  issues:      #{project.issues.count}"
puts "  time_entries:#{TimeEntry.where(project_id: project.id).count}"
puts "  closed:      #{project.issues.joins(:status).where(issue_statuses: { is_closed: true }).count}"
puts "  open:        #{project.issues.joins(:status).where(issue_statuses: { is_closed: false }).count}"
