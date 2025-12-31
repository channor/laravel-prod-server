## Laravel prod server

Simple scripts to run in terminal to update, upgrade, and install dependencies on a fresh Ubuntu server.

1. **Server basics**

   * Update OS packages, set timezone, create a non-root deploy user, harden SSH (keys only), enable firewall (UFW), and basic security (fail2ban / unattended-upgrades).

2. **Install core stack**

   * Install **Nginx**, **PHP-FPM** (your target PHP version), required PHP extensions (mbstring, xml, curl, zip, bcmath, intl, gd/imagick, mysql/pgsql, redis, etc.), and **Git**.

3. **Install Composer + Node tooling**

   * Install **Composer** (system-wide) and **Node.js + npm/pnpm** (for Vite builds).

4. **Install & configure database**

   * Install **MySQL/MariaDB or PostgreSQL**.
   * Create DB + user, set strong password, configure bind-address / remote access (usually *off*), and confirm connectivity.

5. **Optional but common services**

   * **Redis** (cache/queue), **Supervisor** (queue workers), **S3-compatible storage** creds, **Meilisearch/Scout** if used.

6. **Create app directory + ownership**

   * Decide path (e.g. `/var/www/yourapp`), set owner to deploy user, and ensure the web server user (often `www-data`) can write only where needed.

7. **Clone the repository**

   * Set up SSH deploy key (or HTTPS token) and `git clone` into the app directory (often using a release directory strategy if you want zero-downtime deploys).

8. **Create `.env` for production**

   * Copy from `.env.example`, set `APP_ENV=production`, `APP_DEBUG=false`, `APP_URL`, DB credentials, cache/queue/mail settings, trusted proxies, session domain, etc.

9. **Install PHP dependencies**

   * Run `composer install --no-dev --optimize-autoloader` (and ensure required PHP extensions are installed if Composer complains).

10. **Generate key + configure encryption**

* Run `php artisan key:generate` (and ensure any APP_KEY/Secrets rotation plan if you already have encrypted data).

11. **Set correct writable permissions**

* Only these should be writable by the web server/process user:

  * `storage/` (all)
  * `bootstrap/cache/`
* Everything else should be read-only for the web server user.

12. **Laravel storage symlink**

* Run `php artisan storage:link` if you serve uploads via `public/storage`.

13. **Run migrations (and seeds if needed)**

* `php artisan migrate --force` (and only seed if your prod process requires it).

14. **Build frontend assets**

* `npm ci` (or `pnpm i --frozen-lockfile`) then `npm run build` (ensure built assets end up in `public/build` for Vite).

15. **Optimize Laravel for production**

* `php artisan config:cache`
* `php artisan route:cache` (only if safe for your app)
* `php artisan view:cache`
* `php artisan event:cache` (optional)

16. **Configure Nginx site**

* Point `root` to `.../public`
* `try_files $uri $uri/ /index.php?$query_string;`
* PHP upstream to correct `php-fpm` socket/version
* Deny access to dotfiles, `.env`, etc.
* Set client body size/timeouts as needed.

17. **Enable HTTPS**

* Use Let’s Encrypt (Certbot) for SSL, force HTTPS redirect, and add HSTS if appropriate.

18. **Queues + scheduler**

* If using queues: set up **Supervisor** to run `php artisan queue:work` (or Horizon).
* Add cron for scheduler: `* * * * * php /path/artisan schedule:run >> /dev/null 2>&1`

19. **Logging & permissions sanity**

* Ensure logs write to `storage/logs`, configure log rotation, verify PHP-FPM/Nginx can’t write outside `storage/` + `bootstrap/cache/`.

20. **Smoke test + go live**

* Hit health endpoints, login flows, file uploads, queues, mail, and check Nginx/PHP-FPM error logs.
* Confirm `APP_DEBUG=false`, correct `APP_URL`, correct trusted proxy config (especially behind load balancers/CDNs).

21. **Production hygiene**

* Backups (DB + storage), monitoring/alerts, uptime checks, and a repeatable deploy procedure (pull, install, build, migrate, cache, restart workers).
