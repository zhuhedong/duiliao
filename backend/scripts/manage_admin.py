#!/usr/bin/env python3
"""Create or promote an admin (or staff) account.

There is no default admin account: normal registration always creates a
``user``-role account. The collector's write operations (collect / draw sync /
judge / source edits / catalog scan) require ``staff`` or ``admin``, so use this
script once to bootstrap a privileged account.

Run from the ``backend`` directory with the project venv, e.g.:

    # create a brand-new admin (prompts for the password if omitted)
    .venv/bin/python scripts/manage_admin.py create --email admin@example.com

    # or with an explicit password and username
    .venv/bin/python scripts/manage_admin.py create --username admin --password 'S3cret!!' --role admin

    # promote an existing account (matched by email / phone / username)
    .venv/bin/python scripts/manage_admin.py promote --identifier admin@example.com --role admin

    # list current staff/admin accounts
    .venv/bin/python scripts/manage_admin.py list
"""
from __future__ import annotations

import argparse
import getpass
import sys
from pathlib import Path

# Allow running as `python scripts/manage_admin.py` from backend/.
sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from sqlalchemy import or_, select  # noqa: E402

from app.core.security import hash_password  # noqa: E402
from app.db.session import SessionLocal, init_db  # noqa: E402
from app.models.user import RegistrationSource, User, UserRole, UserStatus  # noqa: E402


def _find(db, identifier: str) -> User | None:
    identifier = identifier.strip()
    return db.scalars(
        select(User).where(
            or_(
                User.email == identifier.lower(),
                User.phone == identifier,
                User.username == identifier,
            )
        )
    ).first()


def _read_password(provided: str | None) -> str:
    if provided:
        return provided
    pw = getpass.getpass("Password: ")
    if pw != getpass.getpass("Confirm password: "):
        sys.exit("Passwords do not match.")
    if len(pw) < 8:
        sys.exit("Password must be at least 8 characters.")
    return pw


def cmd_create(args: argparse.Namespace) -> None:
    if not (args.email or args.username or args.phone):
        sys.exit("Provide at least one of --email / --username / --phone.")
    role = UserRole(args.role)
    with SessionLocal() as db:
        email = args.email.lower() if args.email else None
        if _find(db, args.email or args.username or args.phone):
            sys.exit("An account with those details already exists. Use `promote` instead.")
        user = User(
            email=email,
            phone=args.phone,
            username=args.username,
            display_name=args.display_name or args.username or "Administrator",
            password_hash=hash_password(_read_password(args.password)),
            role=role,
            status=UserStatus.ACTIVE,
            email_verified=bool(email),
            registration_source=RegistrationSource.API,
        )
        db.add(user)
        db.commit()
        db.refresh(user)
        print(f"Created {role.value} account: id={user.id} "
              f"email={user.email or '-'} username={user.username or '-'}")


def cmd_promote(args: argparse.Namespace) -> None:
    role = UserRole(args.role)
    with SessionLocal() as db:
        user = _find(db, args.identifier)
        if user is None:
            sys.exit(f"No account matches '{args.identifier}'.")
        user.role = role
        if args.password:
            user.password_hash = hash_password(args.password)
        db.commit()
        print(f"Updated {args.identifier}: role={role.value}"
              + (" (password reset)" if args.password else ""))


def cmd_list(_: argparse.Namespace) -> None:
    with SessionLocal() as db:
        rows = db.scalars(
            select(User).where(User.role.in_([UserRole.ADMIN.value, UserRole.STAFF.value]))
        ).all()
        if not rows:
            print("No staff/admin accounts. Create one with the `create` command.")
            return
        for u in rows:
            role = getattr(u.role, "value", u.role)
            status = getattr(u.status, "value", u.status)
            print(f"- {role:5} id={u.id} email={u.email or '-'} "
                  f"username={u.username or '-'} status={status}")


def main() -> None:
    parser = argparse.ArgumentParser(description="Create or promote an admin/staff account.")
    sub = parser.add_subparsers(dest="cmd", required=True)

    c = sub.add_parser("create", help="create a new privileged account")
    c.add_argument("--email")
    c.add_argument("--username")
    c.add_argument("--phone")
    c.add_argument("--display-name", dest="display_name")
    c.add_argument("--password", help="omit to be prompted securely")
    c.add_argument("--role", choices=["admin", "staff"], default="admin")
    c.set_defaults(func=cmd_create)

    p = sub.add_parser("promote", help="change an existing account's role")
    p.add_argument("--identifier", required=True, help="email / phone / username")
    p.add_argument("--role", choices=["admin", "staff", "user"], default="admin")
    p.add_argument("--password", help="optionally reset the password too")
    p.set_defaults(func=cmd_promote)

    lst = sub.add_parser("list", help="list current staff/admin accounts")
    lst.set_defaults(func=cmd_list)

    args = parser.parse_args()
    init_db()  # ensure tables exist
    args.func(args)


if __name__ == "__main__":
    main()
