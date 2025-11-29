CREATE TABLE cred (
  cred_id  integer primary key,
  freq     integer default 0,
  username text not null,
  password text not null,
  enable   text not null
);
CREATE TABLE devices (
  dev_id     integer primary key,
  hostname   text    not null,
  ip         text    not null,
  cred_id    integer not null,
  last_check integer default 0,
  note       text,
  foreign key (cred_id) references cred(cred_id)
);
CREATE TABLE ip (
  ip_id    integer primary key,
  ip_start integer not null,
  ip       text    not null,
  mask     integer not null,
  dev_id   integer not null,
  foreign key (dev_id) references devices(dev_id)
);
