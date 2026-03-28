# Radicale — CalDAV shared calendar

Radicale is a lightweight CalDAV/CardDAV server (~15 MB image) used to manage
shared calendars for your team or organisation.

## Purpose in this stack

- **Meeting schedule** — recurring meetings, training events, deadlines
- **Reminders** — n8n queries upcoming events and sends reminders to Discord / email
- **Shared access** — all members can subscribe from any CalDAV-capable client

## Configuration

The Radicale config file is bind-mounted from `services/radicale/config`.
By default it uses `htpasswd` authentication with bcrypt. To manage users:

```bash
# Add or update a user (runs inside the container)
docker exec -it radicale htpasswd -B /data/users <username>
```

## Client setup

### Thunderbird
1. **File → New → Calendar → On the Network**
2. URL: `https://<your-domain>/radicale/<username>/`
3. Enter your Radicale username and password

### iOS Calendar
1. **Settings → Calendar → Accounts → Add Account → Other**
2. Add CalDAV account with server `https://<your-domain>/radicale/`

### Android (DAVx⁵)
1. Install [DAVx⁵](https://www.davx5.com/) from F-Droid or Play Store
2. Add account with base URL `https://<your-domain>/radicale/`

## n8n integration

n8n can query Radicale's CalDAV API to fetch upcoming events and trigger
reminder workflows. Use the HTTP Request node with CalDAV `REPORT` method
against `http://radicale:5232/<username>/<calendar>/`.

> For full documentation see the
> [Radicale documentation](https://radicale.org/v3.html).
