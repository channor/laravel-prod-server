Agent, create all needed scripts with options (with defaults) to each step of setting up an environment. This repo will be public, so we will have run-instructions in README.md, how to run each script without cloning repo. 
The core of this package is to update a fresh Ubuntu OS and add optionally security package(s) with default configuration to make it work, NGINX, PHP-FPM, Git, Composer. Node is optional. PHP version minimum 8.2, but can be set to a higher version. PHP-extensions list. 
Optionally install and setup MySql with a new database, root user, database user+password. Password should be random generated or specified if wanted. The Mysql Database Script should also work "alone", to setup a new database with two new users. One user for migrations, and one user which has priveleges only needed for the web/app-domain.
Redis, Supervisor is optional.
Create a app directory from default, or from user input.
Create a SSH keypair, output the key to use on Github. Set key default to Github
Clone repo, using the key.
Install letsencrypt (optional) and create a certificate.
Setup a NGINX conf file to the public folder or the folder from a user input. Force HTTPS only if chosen (cert can update later).
Run `composer install --no-dev --optimize-autoloader`.
Set correct writable permissions to files and folders.
`cp .env.example .env` if exists, and set defaults `APP_ENV=production`, `APP_DEBUG=false`, `APP_URL=`{user_input}` and the DB credentials from earlier step.
Ask to symlink and run `php artisan storage:link`.
Run migrations.
Optimize laravel.

Agent, make these scripts to work alone, but also as a single run. Make tests to see that the scripts work as wanted.
