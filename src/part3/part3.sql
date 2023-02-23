-- 1) Написать функцию, возвращающую таблицу TransferredPoints в более человекочитаемом виде
-- Ник пира 1, ник пира 2, количество переданных пир поинтов.
-- Количество отрицательное, если пир 2 получил от пира 1 больше поинтов.


DROP FUNCTION IF EXISTS fnc_transferred_points();

CREATE OR REPLACE FUNCTION fnc_transferred_points()
    RETURNS TABLE
            (
                "Peer1"        varchar,
                "Peer2"        varchar,
                "PointsAmount" integer
            )
AS
$$
WITH tmp AS (SELECT tp.checkingPeer,
                    tp.checkedPeer,
                    tp.pointsamount
             FROM TransferredPoints tp
                      INNER JOIN TransferredPoints ON tp.checkingPeer = tp.checkedPeer
                 AND tp.checkedPeer = tp.checkingPeer)
    (SELECT checkingPeer,
            checkedPeer,
            sum(result.pointsamount)
     FROM (SELECT tp.checkingPeer, tp.checkedPeer, tp.pointsamount
           FROM TransferredPoints tp
           UNION
           SELECT t.checkedPeer, t.checkingPeer, -t.pointsamount
           FROM tmp t) AS result
     GROUP BY 1, 2)
EXCEPT
SELECT tmp.checkingPeer,
       tmp.checkedPeer,
       tmp.pointsamount
FROM tmp;
$$ LANGUAGE sql;

-- Тестовый запрос.
SELECT *
FROM fnc_transferred_points();


-- 2) Написать функцию, которая возвращает таблицу вида: ник пользователя, название проверенного задания, кол-во полученного XP
-- В таблицу включать только задания, успешно прошедшие проверку (определять по таблице Checks).
-- Одна задача может быть успешно выполнена несколько раз. В таком случае в таблицу включать все успешные проверки.

DROP FUNCTION IF EXISTS fnc_successful_checks;

CREATE or replace FUNCTION fnc_successful_checks()
    RETURNS TABLE
            (
                peer     varchar,
                task     varchar,
                xpamount integer
            )
AS
$tab$
BEGIN
    RETURN QUERY
        WITH one AS (SELECT checks.id
                     FROM checks
                              INNER JOIN p2p ON checks.id = p2p."Check"
                              LEFT JOIN Verter ON checks.id = Verter."Check"
                     WHERE p2p.state = 'Success' AND checks.task > 'C6_s21_matrix'
                        OR p2p.state = 'Success' AND Verter.state = 'Success'

                     GROUP BY checks.id)

        SELECT checks.peer,
               checks.task,
               xp.xpamount
        FROM one
                 INNER JOIN checks ON one.id = checks.id
                 INNER JOIN XP ON one.id = XP."Check"
        GROUP BY checks.peer, checks.task, xp.xpamount;
END
$tab$ LANGUAGE plpgsql;

SELECT *
FROM fnc_successful_checks();

-- 3) Написать функцию, определяющую пиров, которые не выходили из кампуса в течение всего дня
-- Параметры функции: день, например 12.05.2022.
-- Функция возвращает только список пиров.


DROP FUNCTION IF EXISTS fnc_check_date(peer_date date);

CREATE OR REPLACE FUNCTION fnc_check_date(peer_date date)
    RETURNS TABLE
            (
                peer varchar
            )
AS
$$
SELECT peer
FROM timetracking
WHERE "Date" = peer_date
  AND state = '1'
GROUP BY peer
HAVING SUM(state) = 1
$$ LANGUAGE sql;

-- Тестовый запрос.
SELECT *
FROM fnc_check_date('2022-06-09');

-- 4) Найти процент успешных и неуспешных проверок за всё время
-- Формат вывода: процент успешных, процент неуспешных

DROP PROCEDURE IF EXISTS pr_success_percent(IN ref refcursor);

CREATE OR REPLACE PROCEDURE pr_success_percent(IN ref refcursor)
AS
$$
BEGIN
    OPEN ref FOR
        WITH tmp AS (SELECT id,
                            "Check",
                            state,
                            "Time"
                     FROM p2p
                     WHERE NOT (state = 'Start')
                     UNION ALL
                     SELECT id,
                            "Check",
                            state,
                            "Time"
                     FROM verter
                     WHERE NOT (state = 'Start'))

        SELECT (cast
            (cast((SELECT count(*)
                   FROM p2p
                   WHERE NOT (state = 'Start')) - count(*) AS numeric) / (SELECT count(*)
                                                                          FROM p2p
                                                                          WHERE NOT (state = 'Start')) *
             100 AS int))                                                                   AS SuccessfulChecks,
               cast
                   (cast(count(*) AS numeric) / (SELECT count(*)
                                                 FROM p2p
                                                 WHERE NOT (state = 'Start')) * 100 AS int) AS UnsuccessfulChecks
        FROM tmp
        WHERE (state = 'Failure');
END;
$$ LANGUAGE plpgsql;

-- Тестовая транзакция.
BEGIN;
CALL pr_success_percent('ref');
FETCH ALL IN "ref";
END;

--- 5) Посчитать изменение в количестве пир поинтов каждого пира по таблице TransferredPoints
-- Результат вывести отсортированным по изменению числа поинтов.
-- Формат вывода: ник пира, изменение в количество пир поинтов

DROP PROCEDURE IF EXISTS pr_points_change(IN ref refcursor);

CREATE OR REPLACE PROCEDURE pr_points_change(IN ref refcursor)
AS
$$
BEGIN
    OPEN ref FOR
        SELECT checkingpeer      AS Peer,
               SUM(pointsamount) AS PointsChange
        FROM (SELECT checkingpeer,
                     SUM(pointsamount) AS pointsamount
              FROM TransferredPoints
              GROUP BY checkingpeer
              UNION ALL
              SELECT checkedpeer,
                     SUM(-pointsamount) AS pointsamount
              FROM TransferredPoints
              GROUP BY checkedpeer) AS change
        GROUP BY checkingpeer
        ORDER BY PointsChange DESC;
END;
$$ LANGUAGE plpgsql;

-- Тестовая транзакция.
BEGIN;
CALL pr_points_change('ref');
FETCH ALL IN "ref";
END;

-- 6) Посчитать изменение в количестве пир поинтов каждого пира по таблице, возвращаемой первой функцией из Part 3
-- Результат вывести отсортированным по изменению числа поинтов.
-- Формат вывода: ник пира, изменение в количество пир поинтов

DROP procedure IF EXISTS pr_transferred_points(IN ref refcursor);

CREATE OR REPLACE PROCEDURE pr_transferred_points(IN ref refcursor)
AS
$$
BEGIN
    OPEN ref FOR
        SELECT "Peer1"           as Peer,
               sum(pointsamount) AS PointsChange
        FROM (SELECT "Peer1",
                     SUM("PointsAmount") AS pointsamount
              FROM fnc_transferred_points()
              GROUP BY "Peer1"
              UNION ALL
              SELECT "Peer2",
                     SUM(-"PointsAmount") AS pointsamount
              FROM fnc_transferred_points()
              GROUP BY "Peer2") AS change
        GROUP BY Peer
        ORDER BY pointschange DESC;
END;
$$ LANGUAGE plpgsql;

-- Тестовая транзакция.
BEGIN;
CALL pr_transferred_points('ref');
FETCH ALL IN "ref";
END;

-- 7) Определить самое часто проверяемое задание за каждый день
-- При одинаковом количестве проверок каких-то заданий в определенный день, вывести их все.
-- Формат вывода: день, название задания

DROP PROCEDURE IF EXISTS pr_max_task_check(IN ref refcursor);

CREATE OR REPLACE PROCEDURE pr_max_task_check(IN ref refcursor)
AS
$$
BEGIN
    OPEN ref FOR
        WITH t1 AS (SELECT "Date"      AS d,
                           checks.task,
                           COUNT(task) AS tc
                    FROM checks
                    GROUP BY checks.task, d)
        SELECT t2.d AS day, t2.task
        FROM (SELECT t1.task,
                     t1.d,
                     rank() OVER (PARTITION BY t1.d ORDER BY tc DESC) AS rank
              FROM t1) AS t2
        WHERE rank = 1
        ORDER BY day;
END
$$ LANGUAGE plpgsql;

-- Тестовая транзакция.
BEGIN;
CALL pr_max_task_check('ref');
FETCH ALL IN "ref";
END;

-- 8) Определить длительность последней P2P проверки
-- Под длительностью подразумевается разница между временем, указанным в записи со статусом "начало", и временем, указанным в записи со статусом "успех" или "неуспех".
-- Формат вывода: длительность проверки

DROP PROCEDURE IF EXISTS pr_check_duration;

CREATE OR REPLACE PROCEDURE pr_check_duration(IN ref refcursor)
AS
$$
DECLARE
    id_check_start int  := (SELECT "Check"
                            FROM p2p
                            WHERE state != 'Start'
                              AND "Check" = (SELECT max("Check") FROM p2p)
                            LIMIT 1);
    id_check_end   int  := (SELECT "Check"
                            FROM p2p
                            WHERE state = 'Start'
                              AND "Check" = (SELECT max("Check") FROM p2p)
                            LIMIT 1);
    starts_check   time := (SELECT "Time"
                            FROM p2p
                            WHERE state != 'Start'
                              AND "Check" = (SELECT max("Check") FROM p2p)
                            LIMIT 1);
    end_check      time := (SELECT "Time"
                            FROM p2p
                            WHERE state = 'Start'
                              AND "Check" = (SELECT max("Check") FROM p2p)
                            LIMIT 1);
BEGIN
    IF id_check_end = id_check_start
    THEN
        OPEN ref FOR
            SELECT starts_check - end_check AS "Duration";
    ELSE
        RAISE NOTICE ' P2P check is not completed ';
    END IF;
END;
$$ LANGUAGE plpgsql;

-- Тестовая транзакция.
BEGIN;
CALL pr_check_duration('ref');
FETCH ALL IN "ref";
END;


-- 9) Найти всех пиров, выполнивших весь заданный блок задач и дату завершения последнего задания
-- Параметры процедуры: название блока, например "CPP".
-- Результат вывести отсортированным по дате завершения.
-- Формат вывода: ник пира, дата завершения блока (т.е. последнего выполненного задания из этого блока)

DROP FUNCTION IF EXISTS fnc_successful_checks_last_task;

CREATE or replace FUNCTION fnc_successful_checks_last_task(mytask varchar)
    RETURNS TABLE
            (
                Peer varchar,
                Day  date
            )
AS
$tab$
BEGIN
    return query
        WITH tasks_current_block AS (SELECT *
                                     FROM tasks
                                     WHERE tasks.title SIMILAR TO concat(mytask, '[0-9]_%')),
             last_task AS (SELECT MAX(title) AS title
                           FROM tasks_current_block),
             date_of_successful_check AS (SELECT checks.peer,
                                                 checks.task,
                                                 checks."Date"
                                          FROM checks
                                                   INNER JOIN p2p ON checks.id = p2p."Check"
                                          WHERE p2p.state = 'Success'
                                          GROUP BY checks.id)

        SELECT dosc.peer   AS Peer,
               dosc."Date" AS Day
        FROM date_of_successful_check dosc
                 INNER JOIN last_task ON dosc.task = last_task.title;
END
$tab$ LANGUAGE plpgsql;

-- Тестовый запрос.
SELECT *
FROM fnc_successful_checks_last_task('C');

-- 10) Определить, к какому пиру стоит идти на проверку каждому обучающемуся
-- Определять нужно исходя из рекомендаций друзей пира, т.е. нужно найти пира, проверяться у которого рекомендует наибольшее число друзей.
-- Формат вывода: ник пира, ник найденного проверяющего

DROP FUNCTION IF EXISTS pr_recommendation_peer(IN Peer varchar, OUT recommendedpeer varchar);

CREATE OR REPLACE FUNCTION pr_recommendation_peer(IN checking_peer varchar)
    RETURNS TABLE
            (
                Peer            varchar,
                RecommendedPeer varchar
            )
AS
$$
BEGIN
    RETURN QUERY
        WITH find_friends AS (SELECT friends.peer2
                              FROM friends
                              WHERE friends.peer1 NOT LIKE checking_peer),
             recommended_peers AS (SELECT recommendations.recommendedpeer AS rp
                                   FROM recommendations
                                            INNER JOIN find_friends ON recommendations.peer = find_friends.peer2
                                   WHERE recommendations.recommendedpeer NOT LIKE checking_peer),
             recommended_peer AS (SELECT recommended_peers.rp,
                                         COUNT(*)
                                  FROM recommended_peers
                                  GROUP BY recommended_peers.rp
                                  ORDER BY 2 DESC
                                  LIMIT 1)
        SELECT (SELECT peers.nickname
                FROM peers
                WHERE peers.nickname = checking_peer),
               (SELECT rp AS RecommendedPeer FROM recommended_peer);
END;
$$
    LANGUAGE plpgsql;

SELECT *
FROM pr_recommendation_peer('Klee');

-- 11) Определить процент пиров, которые:
--
-- Приступили только к блоку 1
-- Приступили только к блоку 2
-- Приступили к обоим
-- Не приступили ни к одному
--
-- Пир считается приступившим к блоку, если он проходил хоть одну проверку любого задания из этого блока (по таблице Checks)
-- Параметры процедуры: название блока 1, например SQL, название блока 2, например A.
-- Формат вывода: процент приступивших только к первом

DROP function fnc_successful_checks_blocks(block1 varchar, block2 varchar);


CREATE FUNCTION fnc_successful_checks_blocks(block1 varchar, block2 varchar)
    RETURNS TABLE
            (
                StartedBlock1      BIGINT,
                StartedBlock2      BIGINT,
                StartedBothBlocks  BIGINT,
                DidntStartAnyBlock BIGINT
            )
AS
$$
DECLARE
    count_peers int := (SELECT COUNT(peers.nickname)
                        FROM peers);
BEGIN
    RETURN QUERY
        WITH startedblock1 AS (SELECT DISTINCT peer
                               FROM Checks
                               WHERE Checks.task SIMILAR TO concat(block1, '[0-9]_%')),
             startedblock2 AS (SELECT DISTINCT peer
                               FROM Checks
                               WHERE Checks.task SIMILAR TO concat(block2, '[0-9]_%')),
             startedboth AS (SELECT DISTINCT startedblock1.peer
                             FROM startedblock1
                                      INNER JOIN startedblock2 ON startedblock1.peer = startedblock2.peer),
             startedoneof AS (SELECT DISTINCT peer
                              FROM ((SELECT * FROM startedblock1) UNION (SELECT * FROM startedblock2)) AS foo),

             count_startedblock1 AS (SELECT count(*) AS count_startedblock1
                                     FROM startedblock1),
             count_startedblock2 AS (SELECT count(*) AS count_startedblock2
                                     FROM startedblock2),
             count_startedboth AS (SELECT count(*) AS count_startedboth
                                   FROM startedboth),
             count_startedoneof AS (SELECT count(*) AS count_startedoneof
                                    FROM startedoneof)


        SELECT ((SELECT count_startedblock1::bigint FROM count_startedblock1) * 100 / count_peers)             AS StartedBlock1,
               ((SELECT count_startedblock2::bigint FROM count_startedblock2) * 100 /
                count_peers)                                                                                   AS StartedBlock2,
               ((SELECT count_startedboth::bigint FROM count_startedboth) * 100 /
                count_peers)                                                                                   AS StartedBothBlocks,
               ((SELECT count_peers - count_startedoneof::bigint FROM count_startedoneof) * 100 /
                count_peers)                                                                                   AS DidntStartAnyBlock;

END
$$
    LANGUAGE plpgsql;

SELECT *
FROM fnc_successful_checks_blocks('C', 'CPP');

-- 12) Определить N пиров с наибольшим числом друзей
-- Параметры процедуры: количество пиров N.
-- Результат вывести отсортированным по кол-ву друзей.
-- Формат вывода: ник пира, количество друзей

DROP PROCEDURE IF EXISTS pr_count_friends;

CREATE OR REPLACE PROCEDURE pr_count_friends(IN ref refcursor, IN limits int)
AS
$$
BEGIN
    OPEN ref FOR
        SELECT peer1        AS peer,
               count(peer2) AS "FriendsCount"
        FROM friends
        GROUP BY peer
        ORDER BY "FriendsCount" DESC
        LIMIT limits;
END;
$$ LANGUAGE plpgsql;

-- Тестовая транзакция.
BEGIN;
CALL pr_count_friends('ref', 3);
FETCH ALL FROM "ref";
END;


-- 13) Определить процент пиров, которые когда-либо успешно проходили проверку в свой день рождения
-- Также определите процент пиров, которые хоть раз проваливали проверку в свой день рождения.
-- Формат вывода: процент успехов в день рождения, процент неуспехов в день рождения


DROP FUNCTION IF EXISTS fnc_successful_checks_birthday();

CREATE FUNCTION fnc_successful_checks_birthday()
    RETURNS TABLE
            (
                SuccessfulChecks   bigint,
                UnsuccessfulChecks bigint
            )
AS
$$
DECLARE
    checks_count integer := (SELECT MAX(id)
                             FROM checks);
    suck_checks  bigint  := (SELECT COUNT(*)
                             FROM Peers
                                      INNER JOIN Checks ON Peers.birthday = Checks."Date"
                             WHERE Peers.Nickname = Checks.Peer);
BEGIN
    RETURN QUERY
        SELECT (SELECT suck_checks / checks_count * 100)                  AS SuccessfulChecks,
               (SELECT (checks_count - suck_checks) / checks_count * 100) AS UnsuccessfulChecks;
END
$$
    LANGUAGE plpgsql;

SELECT *
FROM fnc_successful_checks_birthday();


-- 14) Определить кол-во XP, полученное в сумме каждым пиром
-- Если одна задача выполнена несколько раз, полученное за нее кол-во XP равно максимальному за эту задачу.
-- Результат вывести отсортированным по кол-ву XP.
-- Формат вывода: ник пира, количество XP

DROP PROCEDURE IF EXISTS pr_peer_xp_sum(ref refcursor);

CREATE OR REPLACE PROCEDURE pr_peer_xp_sum(IN ref refcursor)
AS
$$
BEGIN
    OPEN ref FOR
        SELECT peer,
               SUM(xpamount) AS "XP"
        FROM (SELECT peer, task, MAX(xpamount) AS xpamount
              FROM xp
                       INNER JOIN checks c on c.id = xp."Check"
              GROUP BY peer, task) AS "XP"
        GROUP BY peer
        ORDER BY "XP" DESC;
END
$$ LANGUAGE plpgsql;

BEGIN;
CALL pr_peer_xp_sum('ref');
FETCH ALL FROM "ref";
END;

-- 15) Определить всех пиров, которые сдали заданные задания 1 и 2, но не сдали задание 3
-- Параметры процедуры: названия заданий 1, 2 и 3.
-- Формат вывода: список пиров

DROP FUNCTION IF EXISTS fnc_successful_tasks_1_2(task1 varchar, task2 varchar, task3 varchar);

CREATE FUNCTION fnc_successful_tasks_1_2(task1 varchar, task2 varchar, task3 varchar)
    RETURNS TABLE
            (
                Peer varchar
            )
AS
$$
WITH suck_task1 AS (SELECT peer
                    FROM fnc_successful_checks() AS successful_checks
                    WHERE successful_checks.task LIKE task1),
     suck_task2 AS (SELECT peer
                    FROM fnc_successful_checks() AS successful_checks
                    WHERE successful_checks.task LIKE task2),
     suck_task3 AS (SELECT Peer
                    FROM fnc_successful_checks() AS successful_checks
                    WHERE successful_checks.task NOT LIKE task3)

SELECT *
FROM ((SELECT * FROM suck_task1) INTERSECT (SELECT * FROM suck_task2) INTERSECT (SELECT * FROM suck_task3)) AS foo;
$$
    LANGUAGE sql;

SELECT *
FROM fnc_successful_tasks_1_2('C2_SimpleBashUtils', 'C3_s21_string+', 'DO3_Linux_Monitoring');

-- 16) Используя рекурсивное обобщенное табличное выражение, для каждой задачи вывести кол-во предшествующих ей задач
-- То есть сколько задач нужно выполнить, исходя из условий входа, чтобы получить доступ к текущей.
-- Формат вывода: название задачи, количество предшествующих

DROP FUNCTION IF EXISTS fnc_count_parent_tasks();

CREATE OR REPLACE FUNCTION fnc_count_parent_tasks()
    RETURNS TABLE
            (
                Task      varchar,
                PrevCount integer
            )
AS
$$
WITH RECURSIVE r AS (SELECT CASE
                                WHEN (tasks.parenttask IS NULL) THEN 0
                                ELSE 1
                                END          AS counter,
                            tasks.title,
                            tasks.parenttask AS current_tasks,
                            tasks.parenttask
                     FROM tasks

                     UNION ALL

                     SELECT (CASE
                                 WHEN child.parenttask IS NOT NULL THEN counter + 1
                                 ELSE counter
                         END)                AS counter,
                            child.title      AS title,
                            child.parenttask AS current_tasks,
                            parrent.title    AS parrenttask
                     FROM tasks AS child
                              CROSS JOIN r AS parrent
                     WHERE parrent.title LIKE child.parenttask)
SELECT title        AS Task,
       MAX(counter) AS PrevCount
FROM r
GROUP BY title
ORDER BY 1;
$$
    LANGUAGE sql;

SELECT *
FROM fnc_count_parent_tasks();

-- 17) Найти "удачные" для проверок дни. День считается "удачным", если в нем есть хотя бы N идущих подряд успешных проверки
-- Параметры процедуры: количество идущих подряд успешных проверок N.
-- Временем проверки считать время начала P2P этапа.
-- Под идущими подряд успешными проверками подразумеваются успешные проверки, между которыми нет неуспешных.
-- При этом кол-во опыта за каждую из этих проверок должно быть не меньше 80% от максимального.
-- Формат вывода: список дней

DROP PROCEDURE IF EXISTS pr_lucky_day(ref refcursor);

CREATE OR REPLACE PROCEDURE pr_lucky_day(IN ref refcursor, N int)
AS
$$
BEGIN
    OPEN ref FOR
        WITH t1 AS (SELECT c.id,
                           "Date",
                           peer,
                           v."Check"  AS id_check,
                           t.maxxp    AS max_xp,
                           x.xpamount AS peer_get_xp,
                           v.state
                    FROM checks c
                             INNER JOIN p2p on c.id = p2p."Check" AND (p2p.state = 'Success')
                             INNER JOIN verter v on c.id = v."Check" AND (v.state = 'Success')
                             INNER JOIN tasks t on t.title = c.task
                             INNER JOIN xp x on c.id = x."Check"
                    ORDER BY "Date")
        SELECT "Date"
        FROM t1
        WHERE t1.peer_get_xp > t1.max_xp * 0.8
        GROUP BY "Date"
        HAVING count("Date") >= N;
END
$$ LANGUAGE plpgsql;

-- Тестовая транзакция.
BEGIN;
CALL pr_lucky_day('ref', 3);
FETCH ALL FROM "ref";
END;


-- 18) Определить пира с наибольшим числом выполненных заданий
-- Формат вывода: ник пира, число выполненных заданий

DROP PROCEDURE IF EXISTS pr_max_done_task(ref refcursor);

CREATE OR REPLACE PROCEDURE pr_max_done_task(IN ref refcursor) AS
$$
BEGIN
    OPEN ref FOR
        SELECT peer, count(xpamount) xp
        from xp
                 JOIN checks c on c.id = xp."Check"
        GROUP BY peer
        ORDER BY xp DESC
        LIMIT 1;
END;
$$ LANGUAGE plpgsql;

-- Тестовая транзакция.
BEGIN;
CALL pr_max_done_task('ref');
FETCH ALL FROM "ref";
END;


-- 19) Определить пира с наибольшим количеством XP
-- Формат вывода: ник пира, количество XP

DROP PROCEDURE IF EXISTS pr_max_peer_xp(ref refcursor);

CREATE OR REPLACE PROCEDURE pr_max_peer_xp(IN ref refcursor) AS
$$
BEGIN
    OPEN ref FOR
        SELECT nickname      AS "Peer",
               sum(xpamount) AS "XP"
        FROM peers
                 INNER JOIN checks c on peers.nickname = c.peer
                 INNER JOIN xp x on c.id = x."Check"
        GROUP BY nickname
        ORDER BY "XP" DESC
        LIMIT 1;
END;
$$ LANGUAGE plpgsql;

-- Тестовая транзакция.
BEGIN;
CALL pr_max_peer_xp('ref');
FETCH ALL FROM "ref";
END;

-- 20) Определить пира, который провел сегодня в кампусе больше всего времени
-- Формат вывода: ник пира

DROP FUNCTION fnc_the_longest_interval();

CREATE FUNCTION fnc_the_longest_interval()
    RETURNS TABLE
            (
                peer varchar
            )
AS
$$
WITH go_in AS (SELECT *
               FROM timetracking
               WHERE timetracking.state = 1),
     go_out AS (SELECT *
                FROM timetracking
                WHERE timetracking.state = 2),
     intervals AS (SELECT go_in.peer,
                          MAX(go_out."Time" - go_in."Time") AS interval_in_school
                   FROM go_in
                            INNER JOIN go_out ON go_in."Date" = go_out."Date"
                   WHERE go_in."Date" = current_date
                   GROUP BY go_in.peer
                   ORDER BY interval_in_school DESC)

SELECT peer
FROM intervals
LIMIT 1;
$$
    LANGUAGE sql;

SELECT *
FROM fnc_the_longest_interval();

-- 21) Определить пиров, приходивших раньше заданного времени не менее N раз за всё время
-- Параметры процедуры: время, количество раз N.
-- Формат вывода: список пиров

DROP PROCEDURE IF EXISTS pr_time_spent(IN ref refcursor, checkTime time, N int);

CREATE OR REPLACE PROCEDURE pr_time_spent(IN ref refcursor, checkTime time, N int)
AS
$$
BEGIN
    OPEN ref FOR
        SELECT peer
        FROM timetracking t
        WHERE state = 1
          AND t."Time" < checkTime
        GROUP BY peer
        HAVING count(peer) > N;
END;
$$ LANGUAGE plpgsql;

-- Тестовая транзакция.
BEGIN;
CALL pr_time_spent('ref', '22:00:00', 2);
FETCH ALL IN "ref";
END;

-- 22) Определить пиров, выходивших за последние N дней из кампуса больше M раз
-- Параметры процедуры: количество дней N, количество раз M.
-- Формат вывода: список пиров

DROP PROCEDURE IF EXISTS pr_count_out_of_campus(IN ref refcursor, N int, M int);

CREATE OR REPLACE PROCEDURE pr_count_out_of_campus(IN ref refcursor, N int, M int)
AS
$$
BEGIN
    OPEN ref FOR
        SELECT peer
        FROM (SELECT peer,
                     "Date",
                     count(*) AS counts
              FROM timetracking
              WHERE state = 2
                AND "Date" > (current_date - N)
              GROUP BY peer, "Date"
              ORDER BY "Date") AS res
        GROUP BY peer
        HAVING SUM(counts) > M;
END
$$ LANGUAGE plpgsql;

-- Тестовая транзакция.
BEGIN;
CALL pr_count_out_of_campus('ref', 140, 0);
FETCH ALL IN "ref";
END;

-- 23) Определить пира, который пришел сегодня последним
-- Формат вывода: ник пира

DROP PROCEDURE IF EXISTS pr_last_current_online(IN ref refcursor);

CREATE OR REPLACE PROCEDURE pr_last_current_online(IN ref refcursor)
AS
$$
BEGIN
    OPEN ref FOR
        SELECT peer
        FROM timetracking
        WHERE "Date" = current_date
          AND state = 1
        ORDER BY "Time" DESC
        LIMIT 1;
END;
$$ LANGUAGE plpgsql;

-- Тестовая транзакция.
BEGIN;
CALL pr_last_current_online('ref');
FETCH ALL IN "ref";
END;

-- 24) Определить пиров, которые выходили вчера из кампуса больше чем на N минут
-- Параметры процедуры: количество минут N.
-- Формат вывода: список пиров

DROP FUNCTION to_minutes(t time);

CREATE OR REPLACE FUNCTION to_minutes(t time without time zone)
    RETURNS integer AS
$BODY$
DECLARE
    hs INTEGER := (SELECT(EXTRACT(HOUR FROM t::time) * 60 * 60));
    ms INTEGER := (SELECT (EXTRACT(MINUTES FROM t::time)));
BEGIN
    SELECT (hs + ms) INTO ms;
    RETURN ms;
END;
$BODY$
    LANGUAGE 'plpgsql';

DROP FUNCTION fnc_interval;

CREATE or replace FUNCTION fnc_interval(N int)
    RETURNS TABLE
            (
                peer          varchar,
                time_interval time
            )
AS
$tab$
BEGIN
    return query
        WITH go_in AS (SELECT *
                       FROM timetracking
                       WHERE timetracking.state = 1),
             go_out AS (SELECT *
                        FROM timetracking
                        WHERE timetracking.state = 2)

        SELECT go_in.peer,
               ((go_out."Time" - go_in."Time")::time without time zone)
        FROM go_in
                 INNER JOIN go_out ON go_in.peer = go_out.peer
        WHERE go_in."Date" = go_out."Date"
          AND (SELECT to_minutes((go_out."Time" - go_in."Time")::time without time zone) > N);
END
$tab$ LANGUAGE plpgsql;

SELECT *
FROM fnc_interval(12);


-- 25) Определить для каждого месяца процент ранних входов
-- Для каждого месяца посчитать, сколько раз люди, родившиеся в этот месяц, приходили в кампус за всё время (будем называть это общим числом входов).
-- Для каждого месяца посчитать, сколько раз люди, родившиеся в этот месяц, приходили в кампус раньше 12:00 за всё время (будем называть это числом ранних входов).
-- Для каждого месяца посчитать процент ранних входов в кампус относительно общего числа входов.
-- Формат вывода: месяц, процент ранних входов


DROP FUNCTION IF EXISTS fnc_early_entry();

CREATE FUNCTION fnc_early_entry()
    RETURNS TABLE
            (
                Month        int,
                EarlyEntries BIGINT
            )
AS
$$
BEGIN
    RETURN QUERY
        WITH peers_birthdays AS (SELECT nickname,
                                        date_part('month', birthday) :: text AS date_month
                                 FROM peers),
             months AS (SELECT date_part('month', months) :: text AS "dateMonth"
                        FROM generate_series(
                                     '2023-01-01' :: DATE,
                                     '2023-12-31' :: DATE,
                                     '1 month'
                                 ) AS months),
             entries_in_birth_month AS (SELECT date_month,
                                               peers_birthdays.nickname,
                                               timetracking."Date",
                                               timetracking."Time"
                                        FROM peers_birthdays
                                                 INNER JOIN months ON months."dateMonth" = peers_birthdays.date_month
                                                 INNER JOIN timetracking ON timetracking.peer = peers_birthdays.nickname
                                        WHERE date_part('month', timetracking."Date") :: text =
                                              peers_birthdays.date_month),
             early_entries AS (SELECT *
                               FROM entries_in_birth_month
                               WHERE entries_in_birth_month."Time" < '12:00:00'),

             count_early_entries AS (SELECT months."dateMonth"::int,
                                            COUNT(early_entries.nickname) AS count_ea
                                     FROM months
                                              LEFT JOIN early_entries ON months."dateMonth" = early_entries.date_month
                                     GROUP BY months."dateMonth"),

             count_all_entries as (SELECT months."dateMonth"::int,
                                          COUNT(entries_in_birth_month.nickname) AS count_all
                                   FROM months
                                            LEFT JOIN entries_in_birth_month
                                                      ON months."dateMonth" = entries_in_birth_month.date_month
                                   GROUP BY months."dateMonth")

        SELECT count_all_entries."dateMonth" AS Month,
               count_early_entries.count_ea  AS EarlyEntries
        FROM count_all_entries
                 INNER JOIN count_early_entries ON count_all_entries."dateMonth" = count_early_entries."dateMonth"
        ORDER BY 1;
END
$$ LANGUAGE plpgsql;

SELECT *
FROM fnc_early_entry();
