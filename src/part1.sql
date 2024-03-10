-- creating tables --

create table peers (
    nickname varchar(50) unique primary key not null,
    birthday date not null
);

create table tasks (
    title varchar(50) unique primary key not null,
    parent_task varchar(50) references tasks(title),
    max_xp int check ( max_xp >= 0 ) not null
);

-- create enum for some tables --
create type check_status as enum ('Start', 'Success', 'Failure');

create table p2p (
    id serial primary key,
    check_id bigint not null,
    checking_peer varchar(50) not null,
    state check_status not null,
    time time not null,
    constraint uk_check_id_checking_peer_state unique (check_id, checking_peer, state)
);

create table verter (
    id serial primary key,
    check_id bigint not null,
    state check_status not null,
    time time not null,
    constraint uk_check_id_state unique (check_id, state)
);

create table checks (
    id serial primary key,
    peer varchar(50) not null,
    task varchar(50) not null,
    date date not null,
    constraint fk_checks_task foreign key (task) references tasks(title),
    constraint fk_checks_peer foreign key (peer) references peers(nickname)
);

-- after creating table 'Checks', we add some links with tables 'P2P' and 'Verter' --
alter table p2p add constraint fk_p2p_check_id foreign key (check_id) references checks(id);
alter table p2p add constraint fk_p2p_checking_peer foreign key (checking_peer) references peers(nickname);
alter table verter add constraint fk_verter_check_id foreign key (check_id) references checks(id);

create table transferred_points (
    id serial primary key,
    checking_peer varchar(50) not null,
    checked_peer varchar (50) not null,
    points_amount int not null,
    constraint fk_transferred_points_checking_peer foreign key (checking_peer) references peers(nickname),
    constraint fk_transferred_points_checked_peer foreign key (checked_peer) references peers(nickname)
);

create table friends (
    id serial primary key,
    peer1 varchar(50) not null,
    peer2 varchar(50) not null,
    constraint uk_friends_peer1_peer2 unique (peer1, peer2),
    constraint fk_friends_peer1 foreign key (peer1) references peers(nickname),
    constraint fk_friends_peer2 foreign key (peer2) references peers(nickname)
);

create table recommendations (
    id serial primary key,
    peer varchar(50),
    recommended_peer varchar(50) not null,
    constraint uk_friends_peer_recommended_peer unique (peer, recommended_peer),
    constraint fk_friends_peer foreign key (Peer) references peers(nickname),
    constraint fk_friends_recommended_peer foreign key (recommended_peer) references peers(nickname)
);

create table xp (
    id serial primary key,
    check_id bigint not null,
    xp_amount int check ( xp_amount >= 0 ) not null,
    constraint fk_xp_check_id foreign key (check_id) references checks(id)
);

create table time_tracking (
    id serial primary key,
    peer varchar(50) not null,
    date date not null,
    time time not null,
    state int check ( state = 1 or state = 2 ) not null,
    constraint fk_time_tracking_peer foreign key (peer) references peers(nickname)
);

-- create function and trigger for insert for table 'p2p' --
create or replace function fnc_trg_p2p_insert()
returns trigger as
    $p2p_insert$
    begin
        if new.state = 'Start' then
            if (select p.state
                from p2p p
                where check_id = new.check_id
                order by id desc
                limit 1) = 'Start'
            then raise exception 'The check already has the "Start" status';
            elseif (select p.state
                    from p2p p
                    where check_id = new.check_id
                    order by id desc
                    limit 1) in ('Success', 'Failure')
            then raise exception 'The check has already been completed';
            end if;
            if (select p.state
                from p2p p
                where checking_peer = new.checking_peer
                order by id desc
                limit 1) = 'Start'
            then raise exception 'The peer checks another project';
            elseif (select count(state) - 1
                    from p2p
                    where state = 'Start' and checking_peer = new.checking_peer) >
                   (select count(state)
                    from p2p
                    where state in ('Start', 'Failure') and checking_peer = new.checking_peer)
            then raise exception 'This peer has started another check';
            end if;
        end if;
        if new.state in ('Success', 'Failure') then
            if (select p.state
                from p2p p
                where check_id = new.check_id
                order by id desc
                limit 1) in ('Success', 'Failure')
                then raise exception 'The check has already been completed';
            end if;
            if not exists (select *
                            from p2p
                            where check_id = new.check_id)
                then raise exception 'The check cannot be completed earlier than it started';
            elseif new.time <= (select time
                                from p2p
                                where check_id = new.check_id)
                then raise exception 'The check cannot be completed earlier than it started';
            end if;
            if new.checking_peer != (select checking_peer
                                     from p2p
                                     where check_id = new.check_id)
                then raise exception 'The checking peer does not match the one who started the check';
            end if;
        end if;
        if new.checking_peer = (select peer
                                from checks
                                where id = new.check_id)
            then raise exception 'The peer cannot check himself';
        end if;
        return new;
    end;
    $p2p_insert$
language plpgsql;

create trigger trg_p2p_insert
    before insert on p2p
    for each row
execute function fnc_trg_p2p_insert();

-- create function and trigger for insert for table 'verter' --
create or replace function fnc_trg_verter_insert()
returns trigger as
    $verter_insert$
    begin
        if new.state = 'Start' then
            if (select p.state
                from p2p p
                join checks c on p.check_id = c.id
                where new.check_id = c.id
                order by p.id desc
                limit 1) != 'Success'
                then raise exception 'Verter cannot start to check task which has not got "Success" status from p2p check';
            elseif (select v.state
                    from verter v
                    where v.check_id = new.check_id
                    order by v.id desc
                    limit 1) = 'Start'
            then raise exception 'The check has the "Start" status yet';
            elseif (select v.state
                    from verter v
                    where v.check_id = new.check_id
                    order by v.id desc
                    limit 1) in ('Success', 'Failure')
            then raise exception 'The check has already been completed';
            end if;
        end if;
        if new.state in ('Success', 'Failure') then
            if (select v.state
                from verter v
                where new.check_id = v.check_id
                order by v.id desc
                limit 1) != 'Start'
                then raise exception 'Verter cannot give status "Success" or "Failure" to check, that has not already started';
            elseif (select v.state
                    from verter v
                    where v.check_id = new.check_id
                    order by v.id desc
                    limit 1) in ('Success', 'Failure')
            then raise exception 'The check has already been completed';
            elseif new.time <= (select v.time
                                from verter v
                                where v.check_id = new.check_id)
            then raise exception 'The check cannot be completed earlier than it started';
            end if;
        end if;
    return new;
    end;
    $verter_insert$
language plpgsql;

create trigger trg_verter_insert
    before insert on verter
    for each row
execute function fnc_trg_verter_insert();

-- create view for finding last date --
create view last_date as (
                            select distinct date
                            from time_tracking
                            order by date desc
                            limit 1
                             );

-- create function and trigger for insert for table 'time_tracking' --
create or replace function fnc_trg_time_tracking_insert()
returns trigger as
    $time_tracking_insert$
    begin
        if new.date > (select * from last_date) then
            if (select count(state)
                from time_tracking
                where state = 1 and date = (select * from last_date)) >
               (select count(state)
                from time_tracking
                where state = 2 and date = (select * from last_date))
            then raise exception 'Not all peers have gone home';
            end if;
        end if;
        if new.state = 1 then
            if (select count(state)
                from time_tracking
                where peer = new.peer and date = new.date and state = 1) >
               (select count(state)
                from time_tracking
                where peer = new.peer and date = new.date and state = 2)
            then raise exception 'This peer cannot enter twice in one day without exit';
            end if;
        end if;
        if new.state = 2 then
            if (select count(state)
                from time_tracking
                where peer = new.peer and date = new.date and state = 1) =
               (select count(state)
                from time_tracking
                where peer = new.peer and date = new.date and state = 2)
            then raise exception 'This peer cannot exit twice without additional enter';
            elseif (select count(state)
                    from time_tracking
                    where peer = new.peer and date = new.date and state = 1) = 0
            then raise exception 'Peer cannot exit if he did not enter before';
            elseif new.time < (select time
                               from time_tracking
                               where peer = new.peer and date = new.date and state = 1
                               order by time desc
                               limit 1)
            then raise exception 'The exit time cannot be earlier than the entry time';
            end if;
        end if;
        return new;
    end;
    $time_tracking_insert$
language plpgsql;

create trigger trg_time_tracking_insert
    before insert on time_tracking
    for each row
execute function fnc_trg_time_tracking_insert();

-- inserts for tables --

insert into peers (nickname, birthday)
values ('snake', '1990-01-01'),
       ('raven', '1993-03-03'),
       ('dog', '1995-05-05'),
       ('horse', '1997-07-07'),
       ('cat', '1999-10-10'),
       ('rabbit', '1990-06-22');

insert into tasks (title, parent_task, max_xp)
values ('C1_SimpleBashUtils', null, 350),
       ('C2_s21_string', 'C1_SimpleBashUtils', 600),
       ('C3_s21_decimal', 'C1_SimpleBashUtils', 800),
       ('C4_s21_matrix', 'C3_s21_decimal', 250),
       ('C5_SmartCalc_v1', 'C4_s21_matrix', 800),
       ('CPP1_s21_matrix', 'C5_SmartCalc_v1', 350),
       ('CPP2_s21_containers', 'CPP1_s21_matrix', 800),
       ('CPP3_SmartCalc_v2', 'CPP2_s21_containers', 800),
       ('CPP4_3DViewer_v2', 'CPP3_SmartCalc_v2', 800),
       ('DO1_Linux', 'C2_s21_string',200),
       ('DO2_Linux_Network', 'DO1_Linux',350),
       ('DO3_Simple_Docker', 'DO2_Linux_Network',200),
       ('DO4_CICD', 'DO3_Simple_Docker',200);

insert into time_tracking (peer, date, time, state)
values ('snake', '2024-01-15', '14:34:32', 1),
       ('snake', '2024-01-15', '16:34:32', 2),
       ('dog', '2024-01-15', '10:34:32', 1),
       ('raven', '2024-01-15', '11:34:32', 1),
       ('dog', '2024-01-15', '14:34:32', 2),
       ('raven', '2024-01-15', '17:34:32', 2),
       ('snake', '2024-01-16', '11:34:32', 1),
       ('snake', '2024-01-16', '19:34:32', 2),
       ('dog', '2024-01-16', '10:34:32', 1),
       ('horse', '2024-01-16', '11:59:59', 1),
       ('raven', '2024-01-16', '11:34:32', 1),
       ('dog', '2024-01-16', '14:34:32', 2),
       ('dog', '2024-01-16', '15:34:32', 1),
       ('dog', '2024-01-16', '20:34:32', 2),
       ('horse', '2024-01-16', '18:59:59', 2),
       ('raven', '2024-01-16', '17:34:32', 2),
       ('rabbit', '2024-01-17', '11:34:32', 1),
       ('rabbit', '2024-01-17', '17:34:32', 2),
       ('snake', '2024-01-18', '14:34:32', 1),
       ('snake', '2024-01-18', '16:34:32', 2),
       ('dog', '2024-01-18', '10:34:32', 1),
       ('raven', '2024-01-18', '11:34:32', 1),
       ('dog', '2024-01-18', '14:34:32', 2),
       ('raven', '2024-01-18', '17:34:32', 2),
       ('snake', '2024-02-15', '11:34:32', 1),
       ('snake', '2024-02-15', '16:34:32', 2),
       ('dog', '2024-02-15', '12:34:32', 1),
       ('raven', '2024-02-15', '11:34:32', 1),
       ('dog', '2024-02-15', '14:34:32', 2),
       ('raven', '2024-02-15', '17:34:32', 2),
       ('snake', '2024-02-16', '11:34:32', 1),
       ('snake', '2024-02-16', '19:34:32', 2),
       ('dog', '2024-02-16', '12:34:32', 1),
       ('horse', '2024-02-16', '11:59:59', 1),
       ('raven', '2024-02-16', '11:34:32', 1),
       ('dog', '2024-02-16', '14:34:32', 2),
       ('dog', '2024-02-16', '15:34:32', 1),
       ('dog', '2024-02-16', '20:34:32', 2),
       ('horse', '2024-02-16', '18:59:59', 2),
       ('raven', '2024-02-16', '17:34:32', 2),
       ('rabbit', '2024-02-17', '11:34:32', 1),
       ('rabbit', '2024-02-17', '17:34:32', 2),
       ('snake', '2024-02-18', '11:34:32', 1),
       ('snake', '2024-02-18', '16:34:32', 2),
       ('snake', '2024-03-15', '12:34:32', 1),
       ('snake', '2024-03-15', '16:34:32', 2),
       ('dog', '2024-03-15', '11:34:32', 1),
       ('raven', '2024-03-15', '11:34:32', 1),
       ('dog', '2024-03-15', '14:34:32', 2),
       ('raven', '2024-03-15', '17:34:32', 2),
       ('snake', '2024-03-16', '12:34:32', 1),
       ('snake', '2024-03-16', '19:34:32', 2),
       ('dog', '2024-03-16', '12:34:32', 1),
       ('horse', '2024-03-16', '11:59:59', 1),
       ('raven', '2024-03-16', '11:34:32', 1),
       ('dog', '2024-03-16', '14:34:32', 2),
       ('dog', '2024-03-16', '15:34:32', 1),
       ('dog', '2024-03-16', '20:34:32', 2),
       ('horse', '2024-03-16', '18:59:59', 2),
       ('raven', '2024-03-16', '17:34:32', 2),
       ('rabbit', '2024-03-17', '11:34:32', 1),
       ('rabbit', '2024-03-17', '17:34:32', 2),
       ('snake', '2024-03-18', '12:34:32', 1),
       ('snake', '2024-03-18', '16:34:32', 2),
       ('dog', '2024-03-18', '11:34:32', 1),
       ('dog', '2024-03-18', '14:34:32', 2),
       ('snake', '2024-04-15', '12:34:32', 1),
       ('snake', '2024-04-15', '16:34:32', 2),
       ('dog', '2024-04-15', '11:34:32', 1),
       ('raven', '2024-04-15', '11:34:32', 1),
       ('dog', '2024-04-15', '14:34:32', 2),
       ('raven', '2024-04-15', '17:34:32', 2),
       ('snake', '2024-04-16', '12:34:32', 1),
       ('snake', '2024-04-16', '19:34:32', 2),
       ('dog', '2024-04-16', '12:34:32', 1),
       ('horse', '2024-04-16', '12:59:59', 1),
       ('raven', '2024-04-16', '11:34:32', 1),
       ('dog', '2024-04-16', '14:34:32', 2),
       ('dog', '2024-04-16', '15:34:32', 1),
       ('dog', '2024-04-16', '20:34:32', 2),
       ('horse', '2024-04-16', '18:59:59', 2),
       ('raven', '2024-04-16', '17:34:32', 2),
       ('rabbit', '2024-04-17', '11:34:32', 1),
       ('rabbit', '2024-04-17', '17:34:32', 2),
       ('rabbit', '2024-04-18', '11:34:32', 1),
       ('rabbit', '2024-04-18', '17:34:32', 2),
       ('snake', '2024-04-18', '12:34:32', 1),
       ('snake', '2024-04-18', '16:34:32', 2),
       ('snake', '2024-05-15', '11:34:32', 1),
       ('snake', '2024-05-15', '16:34:32', 2),
       ('dog', '2024-05-15', '12:34:32', 1),
       ('raven', '2024-05-15', '11:34:32', 1),
       ('dog', '2024-05-15', '14:34:32', 2),
       ('raven', '2024-05-15', '17:34:32', 2),
       ('snake', '2024-05-16', '12:34:32', 1),
       ('snake', '2024-05-16', '19:34:32', 2),
       ('dog', '2024-05-16', '12:34:32', 1),
       ('horse', '2024-05-16', '11:59:59', 1),
       ('raven', '2024-05-16', '11:34:32', 1),
       ('dog', '2024-05-16', '14:34:32', 2),
       ('dog', '2024-05-16', '15:34:32', 1),
       ('dog', '2024-05-16', '20:34:32', 2),
       ('horse', '2024-05-16', '18:59:59', 2),
       ('raven', '2024-05-16', '17:34:32', 2),
       ('rabbit', '2024-05-17', '11:34:32', 1),
       ('rabbit', '2024-05-17', '17:34:32', 2),
       ('snake', '2024-05-18', '14:34:32', 1),
       ('snake', '2024-05-18', '16:34:32', 2),
       ('dog', '2024-05-18', '12:34:32', 1),
       ('raven', '2024-05-18', '11:34:32', 1),
       ('dog', '2024-05-18', '14:34:32', 2),
       ('raven', '2024-05-18', '17:34:32', 2),
       ('snake', '2024-06-15', '12:34:32', 1),
       ('snake', '2024-06-15', '16:34:32', 2),
       ('dog', '2024-06-15', '12:34:32', 1),
       ('raven', '2024-06-15', '11:34:32', 1),
       ('dog', '2024-06-15', '14:34:32', 2),
       ('raven', '2024-06-15', '17:34:32', 2),
       ('snake', '2024-06-16', '12:34:32', 1),
       ('snake', '2024-06-16', '19:34:32', 2),
       ('dog', '2024-06-16', '12:34:32', 1),
       ('horse', '2024-06-16', '11:59:59', 1),
       ('raven', '2024-06-16', '12:34:32', 1),
       ('dog', '2024-06-16', '14:34:32', 2),
       ('dog', '2024-06-16', '15:34:32', 1),
       ('dog', '2024-06-16', '20:34:32', 2),
       ('horse', '2024-06-16', '18:59:59', 2),
       ('raven', '2024-06-16', '17:34:32', 2),
       ('rabbit', '2024-06-17', '11:34:32', 1),
       ('rabbit', '2024-06-17', '17:34:32', 2),
       ('snake', '2024-07-15', '11:34:32', 1),
       ('snake', '2024-07-15', '16:34:32', 2),
       ('dog', '2024-07-15', '11:34:32', 1),
       ('raven', '2024-07-15', '11:34:32', 1),
       ('dog', '2024-07-15', '14:34:32', 2),
       ('raven', '2024-07-15', '17:34:32', 2),
       ('snake', '2024-07-16', '12:34:32', 1),
       ('snake', '2024-07-16', '19:34:32', 2),
       ('dog', '2024-07-16', '12:34:32', 1),
       ('horse', '2024-07-16', '11:59:59', 1),
       ('raven', '2024-07-16', '12:34:32', 1),
       ('dog', '2024-07-16', '14:34:32', 2),
       ('dog', '2024-07-16', '15:34:32', 1),
       ('dog', '2024-07-16', '20:34:32', 2),
       ('horse', '2024-07-16', '18:59:59', 2),
       ('raven', '2024-07-16', '17:34:32', 2),
       ('rabbit', '2024-07-17', '11:34:32', 1),
       ('rabbit', '2024-07-17', '17:34:32', 2),
       ('snake', '2024-07-18', '14:34:32', 1),
       ('snake', '2024-07-18', '16:34:32', 2),
       ('dog', '2024-07-18', '10:34:32', 1),
       ('raven', '2024-07-18', '11:34:32', 1),
       ('dog', '2024-07-18', '14:34:32', 2),
       ('raven', '2024-07-18', '17:34:32', 2),
       ('snake', '2024-08-15', '11:34:32', 1),
       ('snake', '2024-08-15', '16:34:32', 2),
       ('dog', '2024-08-15', '11:34:32', 1),
       ('raven', '2024-08-15', '11:34:32', 1),
       ('dog', '2024-08-15', '14:34:32', 2),
       ('raven', '2024-08-15', '17:34:32', 2),
       ('snake', '2024-08-16', '11:34:32', 1),
       ('snake', '2024-08-16', '19:34:32', 2),
       ('dog', '2024-08-16', '11:34:32', 1),
       ('horse', '2024-08-16', '11:59:59', 1),
       ('raven', '2024-08-16', '12:34:32', 1),
       ('dog', '2024-08-16', '14:34:32', 2),
       ('dog', '2024-08-16', '15:34:32', 1),
       ('dog', '2024-08-16', '20:34:32', 2),
       ('horse', '2024-08-16', '18:59:59', 2),
       ('raven', '2024-08-16', '17:34:32', 2),
       ('rabbit', '2024-08-17', '11:34:32', 1),
       ('rabbit', '2024-08-17', '17:34:32', 2),
       ('snake', '2024-08-18', '11:34:32', 1),
       ('snake', '2024-08-18', '16:34:32', 2),
       ('snake', '2024-09-15', '12:34:32', 1),
       ('snake', '2024-09-15', '16:34:32', 2),
       ('dog', '2024-09-15', '12:34:32', 1),
       ('raven', '2024-09-15', '12:34:32', 1),
       ('dog', '2024-09-15', '14:34:32', 2),
       ('raven', '2024-09-15', '17:34:32', 2),
       ('snake', '2024-09-16', '12:34:32', 1),
       ('snake', '2024-09-16', '19:34:32', 2),
       ('dog', '2024-09-16', '11:34:32', 1),
       ('horse', '2024-09-16', '11:59:59', 1),
       ('raven', '2024-09-16', '12:34:32', 1),
       ('dog', '2024-09-16', '14:34:32', 2),
       ('dog', '2024-09-16', '15:34:32', 1),
       ('dog', '2024-09-16', '20:34:32', 2),
       ('horse', '2024-09-16', '18:59:59', 2),
       ('raven', '2024-09-16', '17:34:32', 2),
       ('rabbit', '2024-09-17', '11:34:32', 1),
       ('rabbit', '2024-09-17', '17:34:32', 2),
       ('snake', '2024-10-15', '11:34:32', 1),
       ('snake', '2024-10-15', '16:34:32', 2),
       ('dog', '2024-10-15', '12:34:32', 1),
       ('raven', '2024-10-15', '12:34:32', 1),
       ('dog', '2024-10-15', '14:34:32', 2),
       ('raven', '2024-10-15', '17:34:32', 2),
       ('snake', '2024-10-16', '12:34:32', 1),
       ('snake', '2024-10-16', '19:34:32', 2),
       ('dog', '2024-10-16', '11:34:32', 1),
       ('horse', '2024-10-16', '11:59:59', 1),
       ('raven', '2024-10-16', '12:34:32', 1),
       ('dog', '2024-10-16', '14:34:32', 2),
       ('dog', '2024-10-16', '15:34:32', 1),
       ('dog', '2024-10-16', '20:34:32', 2),
       ('horse', '2024-10-16', '18:59:59', 2),
       ('raven', '2024-10-16', '17:34:32', 2),
       ('rabbit', '2024-10-17', '12:34:32', 1),
       ('rabbit', '2024-10-17', '17:34:32', 2),
       ('snake', '2024-10-18', '11:34:32', 1),
       ('snake', '2024-10-18', '16:34:32', 2),
       ('dog', '2024-10-18', '12:34:32', 1),
       ('raven', '2024-10-18', '12:34:32', 1),
       ('dog', '2024-10-18', '14:34:32', 2),
       ('raven', '2024-10-18', '17:34:32', 2),
       ('snake', '2024-11-15', '12:34:32', 1),
       ('snake', '2024-11-15', '16:34:32', 2),
       ('dog', '2024-11-15', '12:34:32', 1),
       ('raven', '2024-11-15', '12:34:32', 1),
       ('dog', '2024-11-15', '14:34:32', 2),
       ('raven', '2024-11-15', '17:34:32', 2),
       ('snake', '2024-11-16', '12:34:32', 1),
       ('snake', '2024-11-16', '19:34:32', 2),
       ('dog', '2024-11-16', '12:34:32', 1),
       ('horse', '2024-11-16', '11:59:59', 1),
       ('raven', '2024-11-16', '12:34:32', 1),
       ('dog', '2024-11-16', '14:34:32', 2),
       ('dog', '2024-11-16', '15:34:32', 1),
       ('dog', '2024-11-16', '20:34:32', 2),
       ('horse', '2024-11-16', '18:59:59', 2),
       ('raven', '2024-11-16', '17:34:32', 2),
       ('rabbit', '2024-11-17', '12:34:32', 1),
       ('rabbit', '2024-11-17', '17:34:32', 2),
       ('snake', '2024-11-18', '11:34:32', 1),
       ('snake', '2024-11-18', '16:34:32', 2),
       ('snake', '2024-12-15', '11:34:32', 1),
       ('snake', '2024-12-15', '16:34:32', 2),
       ('dog', '2024-12-15', '12:34:32', 1),
       ('raven', '2024-12-15', '12:34:32', 1),
       ('dog', '2024-12-15', '14:34:32', 2),
       ('raven', '2024-12-15', '17:34:32', 2),
       ('snake', '2024-12-16', '12:34:32', 1),
       ('snake', '2024-12-16', '19:34:32', 2),
       ('dog', '2024-12-16', '12:34:32', 1),
       ('horse', '2024-12-16', '11:59:59', 1),
       ('raven', '2024-12-16', '11:34:32', 1),
       ('dog', '2024-12-16', '14:34:32', 2),
       ('dog', '2024-12-16', '15:34:32', 1),
       ('dog', '2024-12-16', '20:34:32', 2),
       ('horse', '2024-12-16', '18:59:59', 2),
       ('raven', '2024-12-16', '17:34:32', 2),
       ('rabbit', '2024-12-17', '12:34:32', 1),
       ('rabbit', '2024-12-17', '17:34:32', 2);

insert into recommendations (peer, recommended_peer)
values ('raven', 'horse'),
       ('horse', 'snake'),
       ('raven', 'snake'),
       ('raven', 'dog'),
       ('cat', 'dog'),
       ('dog', 'cat'),
       ('horse', 'raven'),
       ('snake', 'dog');

insert into friends (peer1, peer2)
values ('snake', 'raven'),
       ('raven', 'dog'),
       ('dog', 'horse'),
       ('horse', 'cat'),
       ('cat', 'snake');

insert into transferred_points (checking_peer, checked_peer, points_amount)
values ('snake', 'dog', 1),
       ('raven', 'snake', 1),
       ('dog', 'snake', 1),
       ('snake', 'dog', 1),
       ('snake', 'raven', 1),
       ('raven', 'dog', 1),
       ('dog', 'snake', 1),
       ('snake', 'cat', 1),
       ('raven', 'dog', 1),
       ('dog', 'snake', 1),
       ('raven', 'cat', 1),
       ('snake', 'raven', 1),
       ('dog', 'snake', 1),
       ('raven', 'dog', 1),
       ('snake', 'dog', 1),
       ('dog', 'snake', 1),
       ('cat', 'dog', 1),
       ('snake', 'dog', 1),
       ('raven', 'dog', 1),
       ('horse', 'dog', 1),
       ('cat', 'horse', 1),
       ('dog', 'cat', 1),
       ('horse', 'cat', 1),
       ('horse', 'snake', 1),
       ('cat', 'dog', 1),
       ('horse', 'dog', 1),
       ('cat', 'dog', 1);

insert into checks (peer, task, date)
values ('snake', 'C1_SimpleBashUtils', '2024-01-01'),
       ('raven', 'CPP1_s21_matrix', '2024-01-01'),
       ('dog', 'DO1_Linux', '2024-01-01'),
       ('snake', 'C2_s21_string', '2024-02-04'),
       ('snake', 'C2_s21_string', '2024-02-05'),
       ('raven', 'CPP2_s21_containers', '2024-02-05'),
       ('dog', 'DO2_Linux_Network', '2024-02-05'),
       ('snake', 'C3_s21_decimal', '2024-02-25'),
       ('raven', 'DO1_Linux', '2024-02-25'),
       ('dog', 'DO3_Simple_Docker', '2024-02-25'),
       ('raven', 'DO1_Linux', '2024-03-03'),
       ('snake', 'C4_s21_matrix', '2024-03-05'),
       ('dog', 'DO4_CICD', '2024-03-20'),
       ('raven', 'CPP3_SmartCalc_v2', '2024-03-27'),
       ('snake', 'C5_SmartCalc_v1', '2024-03-31'),
       ('dog', 'CPP1_s21_matrix', '2024-04-15'),
       ('cat', 'DO1_Linux', '2024-04-15'),
       ('snake', 'CPP1_s21_matrix', '2024-04-20'),
       ('raven', 'CPP4_3DViewer_v2', '2024-04-20'),
       ('horse', 'CPP1_s21_matrix', '2024-04-20'),
       ('cat', 'DO2_Linux_Network', '2024-05-03'),
       ('dog', 'CPP1_s21_matrix', '2024-05-05'),
       ('horse', 'CPP2_s21_containers', '2024-05-10'),
       ('horse', 'CPP3_SmartCalc_v2', '2024-05-31'),
       ('cat', 'DO3_Simple_Docker', '2024-06-13'),
       ('horse', 'CPP4_3DViewer_v2', '2024-06-21'),
       ('cat', 'DO4_CICD', '2024-07-13');

insert into p2p (check_id, checking_peer, state, time)
values (1, 'dog', 'Start', '10:30:30'),
       (1, 'dog', 'Success', '11:00:30'),
       (2, 'snake', 'Start', '12:45:59'),
       (2, 'snake', 'Success', '13:00:40'),
       (3, 'snake', 'Start', '14:15:19'),
       (3, 'snake', 'Success', '14:20:47'),
       (4, 'dog', 'Start', '10:30:30'),
       (4, 'dog', 'Success', '11:00:30'),
       (5, 'raven', 'Start', '10:30:42'),
       (5, 'raven', 'Success', '10:47:12'),
       (6, 'dog', 'Start', '16:47:56'),
       (6, 'dog', 'Success', '17:02:12'),
       (7, 'snake', 'Start', '18:16:00'),
       (7, 'snake', 'Success', '18:30:32'),
       (8, 'cat', 'Start', '09:15:40'),
       (8, 'cat', 'Success', '10:30:32'),
       (9, 'dog', 'Start', '11:15:50'),
       (9, 'dog', 'Failure', '12:02:42'),
       (10, 'snake', 'Start', '13:16:40'),
       (10, 'snake', 'Success', '13:48:24'),
       (11, 'cat', 'Start', '18:16:00'),
       (11, 'cat', 'Success', '18:30:32'),
       (12, 'raven', 'Start', '20:56:00'),
       (12, 'raven', 'Success', '21:30:32'),
       (13, 'snake', 'Start', '14:54:50'),
       (13, 'snake', 'Success', '15:18:47'),
       (14, 'dog', 'Start', '14:54:50'),
       (14, 'dog', 'Success', '15:18:47'),
       (15, 'dog', 'Start', '11:15:50'),
       (15, 'dog', 'Success', '12:02:42'),
       (16, 'snake', 'Start', '11:15:50'),
       (16, 'snake', 'Failure', '12:02:42'),
       (17, 'dog', 'Start', '15:15:50'),
       (17, 'dog', 'Success', '16:02:42'),
       (18, 'dog', 'Start', '15:15:50'),
       (18, 'dog', 'Failure', '16:02:42'),
       (19, 'dog', 'Start', '17:15:50'),
       (19, 'dog', 'Success', '18:02:42'),
       (20, 'dog', 'Start', '20:15:50'),
       (20, 'dog', 'Success', '21:02:42'),
       (21, 'horse', 'Start', '20:15:50'),
       (21, 'horse', 'Success', '21:02:42'),
       (22, 'cat', 'Start', '20:15:50'),
       (22, 'cat', 'Failure', '21:02:42'),
       (23, 'cat', 'Start', '20:15:50'),
       (23, 'cat', 'Success', '21:02:42'),
       (24, 'snake', 'Start', '20:15:50'),
       (24, 'snake', 'Success', '21:02:42'),
       (25, 'dog', 'Start', '20:15:50'),
       (25, 'dog', 'Success', '21:02:42'),
       (26, 'dog', 'Start', '20:15:50'),
       (26, 'dog', 'Failure', '21:02:42'),
       (27, 'dog', 'Start', '20:15:50'),
       (27, 'dog', 'Failure', '21:02:42');

insert into verter (check_id, state, time)
values (1, 'Start', '11:01:00'),
       (1, 'Success', '11:02:00'),
       (4, 'Start', '11:02:00'),
       (4, 'Failure', '11:03:00'),
       (5, 'Start', '10:30:42'),
       (5, 'Success', '10:47:12'),
       (8, 'Start', '09:15:40'),
       (8, 'Success', '10:30:32'),
       (12, 'Start', '20:56:00'),
       (12, 'Success', '21:30:32'),
       (15, 'Start', '11:15:50'),
       (15, 'Success', '12:02:42');

insert into xp (check_id, xp_amount)
values (1, 350),
       (2, 350),
       (3, 150),
       (5, 550),
       (6, 800),
       (7, 300),
       (8, 800),
       (10, 200),
       (11, 200),
       (12, 250),
       (13, 200),
       (14, 750),
       (15, 800),
       (17, 200),
       (19, 800),
       (20, 350),
       (21, 350),
       (23, 800),
       (24, 700),
       (25, 200),
       (27, 300);


-- CSV --

-- ATTENTION!! FOR WORKING WITH PROCEDURES BELOW YOU NEED TO CREATE ANY FOLDER
-- THEN COPY AND PASTE FILE PATH TO CALL PROCEDURE BEFORE /name_file.csv

-- script for export to csv

create or replace procedure export_to_csv
(in table_name varchar, in file_path text, in separator char) as
$import$
begin
    execute format('COPY %s TO ''%s'' DELIMITER ''%s'' CSV HEADER;', table_name, file_path, separator);
end;
$import$
    language plpgsql;

call export_to_csv ('peers', '/Users/vladimirkoloncov/IdeaProjects/info21/csv/peers.csv', ',');
call export_to_csv ('checks', '/Users/vladimirkoloncov/IdeaProjects/info21/csv/checks.csv', ',');
call export_to_csv ('friends', '/Users/vladimirkoloncov/IdeaProjects/info21/csv/friends.csv', ',');
call export_to_csv ('p2p', '/Users/vladimirkoloncov/IdeaProjects/info21/csv/p2p.csv', ',');
call export_to_csv ('recommendations', '/Users/vladimirkoloncov/IdeaProjects/info21/csv/recommendations.csv', ',');
call export_to_csv ('tasks', '/Users/vladimirkoloncov/IdeaProjects/info21/csv/tasks.csv', ',');
call export_to_csv ('time_tracking', '/Users/vladimirkoloncov/IdeaProjects/info21/csv/time_tracking.csv', ',');
call export_to_csv ('transferred_points', '/Users/vladimirkoloncov/IdeaProjects/info21/csv/transferred_points.csv', ',');
call export_to_csv ('verter', '/Users/vladimirkoloncov/IdeaProjects/info21/csv/verter.csv', ',');
call export_to_csv ('xp', '/Users/vladimirkoloncov/IdeaProjects/info21/csv/xp.csv', ',');

-- script for import to csv

create or replace procedure import_from_csv
(in table_name varchar, in file_path text, in separator char) as
$import$
begin
    execute format('COPY %s FROM ''%s'' DELIMITER ''%s'' CSV HEADER;', table_name, file_path, separator);
end;
$import$
language plpgsql;

call import_from_csv ('peers', '/Users/vladimirkoloncov/IdeaProjects/info21/csv/peers.csv', ',');
call import_from_csv ('checks', '/Users/vladimirkoloncov/IdeaProjects/info21/csv/checks.csv', ',');
call import_from_csv ('friends', '/Users/vladimirkoloncov/IdeaProjects/info21/csv/friends.csv', ',');
call import_from_csv ('p2p', '/Users/vladimirkoloncov/IdeaProjects/info21/csv/p2p.csv', ',');
call import_from_csv ('recommendations', '/Users/vladimirkoloncov/IdeaProjects/info21/csv/recommendations.csv', ',');
call import_from_csv ('tasks', '/Users/vladimirkoloncov/IdeaProjects/info21/csv/tasks.csv', ',');
call import_from_csv ('time_tracking', '/Users/vladimirkoloncov/IdeaProjects/info21/csv/time_tracking.csv', ',');
call import_from_csv ('transferred_points', '/Users/vladimirkoloncov/IdeaProjects/info21/csv/transferred_points.csv', ',');
call import_from_csv ('verter', '/Users/vladimirkoloncov/IdeaProjects/info21/csv/verter.csv', ',');
call import_from_csv ('xp', '/Users/vladimirkoloncov/IdeaProjects/info21/csv/xp.csv', ',');
