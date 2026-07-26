# Runs the Redmine demo seeder inside the redmine container.
# Prerequisites: docker compose up, containers healthy.
$ErrorActionPreference = 'Stop'
$seedLocal = Join-Path $PSScriptRoot 'seed_demo.rb'
$seedRemote = '/tmp/seed_demo.rb'

Write-Host 'Copying seeder into container...'
docker cp $seedLocal "redmine:$seedRemote"

Write-Host 'Executing seeder...'
docker exec redmine bundle exec rails runner $seedRemote RAILS_ENV=production
