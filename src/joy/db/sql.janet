# sql.janet
(import ../helper :as helper)


(defn where-op
  "Takes kvs and returns either ? or :name params as strings in a where clause"
  [[k v] &opt positional?]
  (cond
    (= v 'null) "is null"
    :else (if positional?
            (string "= ?")
            (string "= :" k))))


(defn where-clause
  "Takes either a string or a dictionary and returns a where clause with and or that same string"
  [params &opt positional?]
  (if (string? params)
    params
    (->> (pairs params)
         (map |(string (first $) " " (where-op $ positional?)))
         (helper/join-string " and "))))


(defn fetch-options
  "Takes a tuple of kvs and returns order by, limit and offset sql bits"
  [args]
  (when (not (empty? args))
    (let [{:order order :limit limit :offset offset} (apply table args)
          order-by (when (not (nil? order)) (string "order by " order))
          limit (when (not (nil? limit)) (string "limit " limit))
          offset (when (not (nil? offset)) (string "offset " offset))]
      (->> [order-by limit offset]
           (filter |(not (nil? $)))
           (helper/join-string " ")))))


(defn from
  "Takes a table name and where clause params and optional order/limit/offset options and returns a select sql string"
  [table-name params &opt args]
  (default args [])
  (->> [(string "select * from " (helper/snake-case table-name) " where " (where-clause params))
        (fetch-options args)]
       (filter |(not (nil? $)))
       (helper/join-string " ")))


(defn drop-last [arr]
  (->> (reverse arr)
       (drop 1)
       (reverse)))


(defn clone-inside
  "Copies the inner elements of arrays when there are three or more elements"
  [an-array]
  (let [first-val (first an-array)
        inner (drop 1 an-array)
        last-val (last inner)
        inner (drop-last inner)
        cloned-inner (interleave inner inner)]
    (->> [first-val cloned-inner last-val]
         (filter |(not (nil? $)))
         (mapcat identity))))


(defn join
  "Returns a join statement from a tuple"
  [[left right]]
  (string "join " left " on " left ".id = " right "." left "_id"))


(defn fetch-joins
  "Returns several join strings from an array of keywords"
  [keywords]
  (when (> (length keywords) 1)
    (->> (clone-inside keywords)
         (partition 2)
         (map join)
         (reverse)
         (helper/join-string " "))))


(defn fetch-params
  "Returns a table for a where clause of a 'fetch' sql string"
  [path]
  (->> (partition 2 path)
       (filter |(= 2 (length $)))
       (mapcat |(array (keyword (first $) ".id") (last $)))
       (apply table)))


(defn fetch
  "Takes a path and generates join statements along with a where clause. Think 'get-in' for sqlite."
  [path & args]
  (let [keywords (filter keyword? path)
        ids (filter |(not (keyword? $)) path)
        where (when (not (empty? ids))
                (string "where "
                  (->> (fetch-params path)
                       (where-clause))))]
    (->> ["select * from"
          (last keywords)
          (fetch-joins keywords)
          where
          (fetch-options args)]
         (filter |(not (nil? $)))
         (helper/join-string " "))))


(defn insert
  "Returns an insert statement sql string from a dictionary"
  [table-name params]
  (let [columns (->> (keys params)
                     (helper/join-string ", "))
        vals (->> (keys params)
                  (map |(string ":" $))
                  (helper/join-string ", "))]
    (string "insert into " (helper/snake-case table-name) " (" columns ") values (" vals ")")))


(defn insert-all
  "Returns a batch insert statement from an array of dictionaries"
  [table-name arr]
  (let [columns (->> (first arr)
                     (keys)
                     (helper/join-string ", "))
        vals (->> (map keys arr)
                  (mapcat (fn [ks] (string "(" (helper/join-string ","
                                                (map (fn [_] (string "?")) ks))
                                           ")")))
                  (helper/join-string ", "))]
    (string "insert into " (helper/snake-case table-name) " (" columns ") values " vals)))


(defn insert-all-params
  "Returns an array of values from an array of dictionaries for the insert-all sql string"
  [arr]
  (mapcat values arr))


(defn update
  "Returns an update sql string from a dictionary of params representing the set portion of the update statement"
  [table-name params]
  (let [columns (->> (pairs params)
                     (map |(string (first $) " = " (if (= 'null (last $))
                                                     "null"
                                                     (string ":" (last $)))))
                     (helper/join-string ", "))]
    (string "update " (helper/snake-case table-name) " set " columns " where id = :id")))


(defn update-all
  "Returns an update sql string from two dictionaries representing the where clause and the set clause"
  [table-name where-params set-params]
  (let [columns (->> (pairs set-params)
                     (map |(string (first $) " = " (if (= 'null (last $))
                                                     "null"
                                                     (string "?"))))
                     (helper/join-string ", "))]
    (string "update " (helper/snake-case table-name) " set " columns " where " (where-clause where-params true))))


(defn update-all-params
  "Returns an array of params for the update-all sql string"
  [where-params set-params]
  (array/concat
    (values set-params)
    (values where-params)))


(defn delete
  "Returns a delete sql string from a table name and value for the id column"
  [table-name id]
  (string "delete from " (helper/snake-case table-name) " where id = :id"))


(defn delete-all
  "Returns a delete sql string from a table name and value for the id column"
  [table-name params]
  (string "delete from " (helper/snake-case table-name) " where " (where-clause params)))
