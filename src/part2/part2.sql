-- 1)Написать процедуру добавления P2P проверки
-- Параметры: ник проверяемого, ник проверяющего, название задания, статус P2P проверки, время.
-- Если задан статус "начало", добавить запись в таблицу Checks (в качестве даты использовать сегодняшнюю).
-- Добавить запись в таблицу P2P.
-- Если задан статус "начало", в качестве проверки указать только что добавленную запись, иначе указать проверку с незавершенным P2P этапом.

DROP PROCEDURE IF EXISTS pr_p2p_check(checked varchar, checking varchar, taskName varchar, state check_status,
                                      P2Ptime time);

CREATE or replace PROCEDURE pr_p2p_check(checked varchar,
                                         checking varchar,
                                         taskName varchar,
                                         state check_status,
                                         P2Ptime time)
AS
$$
DECLARE
    id_check integer := 0;
BEGIN
    IF state = 'Start'
    THEN
        id_check = (SELECT max(id) FROM checks) + 1;
        INSERT INTO checks (id, peer, task, "Date")
        VALUES (id_check, checked, taskName, (SELECT CURRENT_DATE));
    ELSE
        id_check = (SELECT Checks.id
                    FROM p2p
                             INNER JOIN checks
                                        ON checks.id = p2p."Check"
                    WHERE checkingpeer = checking
                      AND peer = checked
                      AND task = taskName
                    ORDER BY checks.id DESC
                    LIMIT 1);
    END IF;

    INSERT INTO p2p ("Check", checkingpeer, state, "Time")
    VALUES (id_check, checking, state, P2Ptime);
END
$$ LANGUAGE plpgsql;

-- 2) Написать процедуру добавления проверки Verter'ом
-- Параметры: ник проверяемого, название задания, статус проверки Verter'ом, время.
-- Добавить запись в таблицу Verter (в качестве проверки указать проверку соответствующего задания с самым поздним (по времени) успешным P2P этапом)

CREATE or replace PROCEDURE pr_verter_check(nickname varchar, taskName varchar, verterState check_status,
                                            checkTime time)
AS
$$
DECLARE
    id_check integer := (SELECT checks.id
                         FROM p2p
                                  INNER JOIN checks
                                             ON checks.id = p2p."Check" AND p2p.state = 'Success'
                                                 AND checks.task = taskName
                                                 AND checks.peer = nickname
                         ORDER BY p2p."Time"
                         LIMIT 1);
BEGIN
    INSERT INTO verter ("Check", state, "Time")
    VALUES (id_check, verterState, checkTime);
END
$$ LANGUAGE plpgsql;

-- Триггеры.

-- 3) Написать триггер: после добавления записи со статутом "начало" в таблицу P2P, изменить соответствующую запись в таблице TransferredPoints

DROP FUNCTION fnc_transferred_points_after_p2p_start() CASCADE;

CREATE OR REPLACE FUNCTION fnc_transferred_points_after_p2p_start()
    RETURNS TRIGGER AS
$tab$
BEGIN
    IF NEW.state = 'Start' THEN
        WITH peers2 AS (SELECT DISTINCT NEW.checkingpeer,
                                        checks.peer as checkedpeer
                        FROM p2p
                                 INNER JOIN checks ON checks.id = NEW."Check"
                        GROUP BY p2p.checkingpeer, checkedpeer)

        UPDATE transferredpoints
        SET pointsamount = transferredpoints.pointsamount + 1,
            id           = transferredpoints.id
        FROM peers2
        WHERE transferredpoints.checkingpeer = peers2.checkingpeer
          AND transferredpoints.checkedpeer = peers2.checkedpeer;
        RETURN NEW;
    ELSE
        RETURN NULL;
    END IF;
END;
$tab$ LANGUAGE plpgsql;

CREATE TRIGGER trg_transferred_points
    AFTER INSERT
    ON p2p
    FOR EACH ROW
EXECUTE PROCEDURE fnc_transferred_points_after_p2p_start();


SELECT *
FROM transferredpoints
ORDER BY 1;


-- 4) Написать триггер: перед добавлением записи в таблицу XP, проверить корректность добавляемой записи
-- Запись считается корректной, если:
-- Количество XP не превышает максимальное доступное для проверяемой задачи
-- Поле Check ссылается на успешную проверку
-- Если запись не прошла проверку, не добавлять её в таблицу.

DROP PROCEDURE IF EXISTS fnc_xp();

CREATE OR REPLACE FUNCTION fnc_xp()
    RETURNS TRIGGER AS
$trg_xp$
DECLARE
    status varchar(20);
    max_xp integer;
BEGIN
    SELECT tasks.maxxp
    INTO max_xp
    FROM checks
             INNER JOIN tasks ON tasks.title = checks.task;
    SELECT p2p.state
    INTO status
    FROM checks
             INNER JOIN p2p ON checks.id = p2p."Check";

    IF new.xpamount > max_xp THEN
        RAISE EXCEPTION 'xp amount is more than max xp for this task';
    ELSEIF status = 'Failure' THEN
        RAISE EXCEPTION 'check is failure';
    ELSE
        RETURN NEW;
    END IF;
END;
$trg_xp$ LANGUAGE plpgsql;


CREATE TRIGGER trg_xp
    BEFORE INSERT
    ON xp
    FOR EACH ROW
EXECUTE PROCEDURE fnc_xp();


DROP PROCEDURE IF EXISTS fnc_xp();
