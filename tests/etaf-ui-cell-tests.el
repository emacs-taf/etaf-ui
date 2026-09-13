;;; etaf-ui-cell-tests.el --- Reusable Table cell contracts -*- lexical-binding: t; -*-

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'etaf-ui)

(defvar etaf-ui-cell-test--states nil)
(defvar etaf-ui-cell-test--removed nil)
(defvar etaf-ui-cell-test--calls nil)
(defvar etaf-ui-cell-test--disposed nil)
(defvar etaf-ui-cell-test--mounted nil)
(defvar etaf-ui-cell-test--observed nil)

(defun etaf-ui-cell-test--row-key (row)
  "Return ROW's stable identity."
  (plist-get row :id))

(defun etaf-ui-cell-test--name (row)
  "Return ROW's name, recording factory evaluation for locality assertions."
  (push (plist-get row :id) etaf-ui-cell-test--calls)
  (plist-get row :name))

(defun etaf-ui-cell-test--hosts (buffer class)
  "Return reference/property pairs for Hosts with CLASS in BUFFER."
  (let (hosts)
    (maphash
     (lambda (ref props)
       (when (member class (split-string (or (plist-get props :class) "")))
         (push (cons ref props) hosts)))
     (etaf-runtime-host-props (etaf-runtime-for-buffer buffer)))
    hosts))

(defmacro etaf-ui-cell-test--with-buffer (name &rest body)
  "Execute BODY with a temporary mounted buffer bound to NAME."
  (declare (indent 1) (debug (symbolp body)))
  `(let ((,name (generate-new-buffer " *etaf-ui-cells*")))
     (unwind-protect (progn ,@body)
       (when-let* ((runtime (etaf-runtime-for-buffer ,name)))
         (etaf-unmount runtime))
       (when (buffer-live-p ,name) (kill-buffer ,name)))))

(etaf-define-component etaf-ui-cell-test-counter (&key row field value)
  "Retain one independent counter at the consuming row/column position."
  :setup
  (let* ((id (list (plist-get row :id) field))
         (count (etaf-ref 0))
         (ref (make-symbol "etaf-cell-counter")))
    (push (list id count ref) etaf-ui-cell-test--states)
    (etaf-on-unmounted (lambda () (push id etaf-ui-cell-test--removed)))
    (list count ref))
  :render
  (let* ((state (etaf-state))
         (count (car state)))
    (etaf-node
     'etaf-button
     (list :label (format "%s:%s:%s%s" (plist-get row :id) field
                          (etaf-value count) (if value (concat ":" value) ""))
           :ref (cadr state)
           :on-press (lambda () (cl-incf (etaf-value count))))
     nil)))

(etaf-define-component etaf-ui-cell-test-resource (&key row pulse)
  "Expose public lifecycle and subscription observations for one cell."
  :setup
  (let ((id (plist-get row :id))
        (count (etaf-ref 0))
        (ref (make-symbol "etaf-cell-resource")))
    (push (list id count ref) etaf-ui-cell-test--states)
    (etaf-on-scope-dispose
     (lambda () (push ref etaf-ui-cell-test--disposed)))
    (etaf-on-mounted (lambda () (push ref etaf-ui-cell-test--mounted)))
    (etaf-on-unmounted (lambda () (push ref etaf-ui-cell-test--removed)))
    (etaf-watch pulse
                (lambda (value _old)
                  (push (cons ref value) etaf-ui-cell-test--observed)))
    (list count ref))
  :render
  (let ((count (car (etaf-state))) (ref (cadr (etaf-state))))
    (etaf-node
     'etaf-button
     (list :label (format "%s:%d" (plist-get row :id) (etaf-value count))
           :ref ref :on-press (lambda () (cl-incf (etaf-value count))))
     nil)))

(defun etaf-ui-cell-test--counter-column (field)
  "Return a custom FIELD column containing independent state."
  (list :key field :label (symbol-name field) :width 12
        :cell (lambda (row)
                (etaf-node 'etaf-ui-cell-test-counter
                           (list :row row :field field) nil))))

(etaf-define-component etaf-ui-cell-test-context (&key shared)
  "Consume Context and Theme where this reusable cell is mounted."
  :setup (etaf-inject 'etaf-ui-cell-test-context nil t)
  :view
  (text :class "cell-context" :color (etaf-theme-token :cell-color)
        (expr (format "%s:%d" (etaf-state) (etaf-value shared))))
  :styles (styles (".cell-context" :font-weight bold)))

(etaf-define-component etaf-ui-cell-test-provider
    (&key label color columns controller)
  "Provide a local LABEL and COLOR around Table or CONTROLLER's Grid."
  :setup
  (progn
    (etaf-provide 'etaf-ui-cell-test-context label)
    (etaf-theme-provide (list :cell-color color))
    nil)
  :render
  (if controller
      (etaf-node 'etaf-data-grid
                 (list :controller controller :columns columns
                       :row-key #'etaf-ui-cell-test--row-key) nil)
    (etaf-node 'etaf-table
               (list :rows '((:id 1)) :columns columns
                     :row-key #'etaf-ui-cell-test--row-key) nil)))

(etaf-define-component etaf-ui-cell-test-factory-author
    (&key shared controller secret)
  "Author one ordinary factory reused under two consumer Contexts."
  :setup
  (progn
    (etaf-provide 'etaf-ui-cell-test-context "Author")
    (etaf-theme-provide '(:cell-color "magenta"))
    (list shared 'author-private-state))
  :render
  (let* ((captured (car (etaf-state)))
         (factory
          (lambda (_row)
            (let ((context (etaf-inject 'etaf-ui-cell-test-context nil t)))
              (push (list context
                          (condition-case nil (etaf-state)
                            (etaf-component-definition-error 'unavailable))
                          (etaf-current-prop 'secret))
                    etaf-ui-cell-test--calls)
              (etaf-node
               'text
               (list :class "cell-author-private cell-factory-consumer"
                     :color (etaf-theme-token :cell-color))
               (list (format "%s:%d" context (etaf-value captured)))))))
         (columns (list (list :key :name :width '(ch 18) :cell factory))))
    (etaf-node
     'column nil
     (list
      (etaf-node 'text '(:class "cell-author-private cell-author-local")
                 (list secret))
      (etaf-node 'etaf-ui-cell-test-provider
                 (list :label "Table" :color "red" :columns columns) nil)
      (etaf-node 'etaf-ui-cell-test-provider
                 (list :label "Grid" :color "blue" :columns columns
                       :controller controller) nil))))
  :styles
  (styles (".cell-author-private" :font-weight bold :font-style italic)))

(ert-deftest etaf-ui-cell-columns-require-unique-non-nil-keys ()
  "Reject ambiguous column identity with its index and offending key."
  (dolist (columns '(((:label "Missing"))
                     ((:key :name) (:key :name))))
    (etaf-ui-cell-test--with-buffer buffer
      (let ((message
             (error-message-string
              (should-error
               (etaf-mount
                buffer
                (etaf-view
                 (etaf-table :columns columns :rows nil
                             :row-key #'etaf-ui-cell-test--row-key)))))))
        (should (string-match-p "column" message))
        (should (string-match-p (if (= (length columns) 1) "1" "2")
                                message))
        (should (string-match-p (if (= (length columns) 1) "nil" ":name")
                                message))))))

(ert-deftest etaf-ui-cell-custom-factory-bypasses-fixed-text ()
  "Custom fixed-width columns mount their controls as ordinary Views."
  (let ((columns (list (list :key :action :width 12 :label "Action"
                            :cell (lambda (row)
                                    (etaf-node 'text nil
                                               (list (plist-get row :name))))))))
    (should-not (etaf-ui--table-fixed-row-text '(:name "Ada") columns))
    (etaf-ui-cell-test--with-buffer buffer
      (etaf-mount
       buffer
       (etaf-view
        (etaf-table :columns columns :rows '((:id 1 :name "Ada"))
                    :row-key #'etaf-ui-cell-test--row-key)))
      (with-current-buffer buffer
        (should (string-match-p "Ada" (buffer-string)))))))

(ert-deftest etaf-ui-cell-stateless-table-keeps-pure-render-support ()
  "Automatic row references do not introduce setup state into plain Tables."
  (dolist (columns '(((:key :name :width 12))
                     ((:key :name :width 12 :cell etaf-ui-cell-test--name))))
    (should
     (ebox-canonical-input-p
      (etaf-render
       (etaf-view
        (etaf-table :columns columns :rows '((:id 1 :name "Ada"))
                    :row-key #'etaf-ui-cell-test--row-key)))))))

(ert-deftest etaf-ui-cell-shares-factory-with-consumer-context-and-theme ()
  "One factory uses each Table/Grid's Context and an explicitly shared ref."
  (let* ((shared (etaf-ref 0))
         (columns
          (list (list :key :context :width 18
                      :cell (lambda (_row)
                              (etaf-node 'etaf-ui-cell-test-context
                                         (list :shared shared) nil)))))
         (source (etaf-data-memory-source '((:id 1)) :id-key :id))
         (controller (etaf-data-controller source :auto-load t)))
    (unwind-protect
        (etaf-ui-cell-test--with-buffer buffer
          (etaf-mount
           buffer
           (etaf-view
            (column
             (etaf-ui-cell-test-provider :label "Table" :color "red"
                                        :columns columns)
             (etaf-ui-cell-test-provider :label "Grid" :color "blue"
                                        :columns columns :controller controller))))
          (setf (etaf-value shared) 7)
          (with-current-buffer buffer
            (should (string-match-p "Table:7" (buffer-string)))
            (should (string-match-p "Grid:7" (buffer-string))))
          (let ((hosts (etaf-ui-cell-test--hosts buffer "cell-context")))
            (should (= 2 (length hosts)))
            (should (equal '("blue" "red")
                           (sort (mapcar (lambda (host)
                                           (plist-get (cdr host) :color))
                                         hosts)
                                 #'string<)))
            (dolist (host hosts)
              (should (eq 'bold (plist-get (cdr host) :font-weight))))))
      (etaf-data-stop controller))))

(ert-deftest etaf-ui-cell-ordinary-output-and-text-mode-switch ()
  "Accept nil/string/Host/fragment/sequences and return to compact text rows."
  (let* ((columns (etaf-ref '((:key :name :label "Name" :width 12))))
         (rows '((:id 1 :name "Default")))
         (factory
          (lambda (_row)
            (list nil "prefix" (etaf-node 'text nil '("host"))
                  (etaf-node 'fragment nil '("fragment"))))))
    (etaf-ui-cell-test--with-buffer buffer
      (etaf-mount
       buffer
       (etaf-view
        (etaf-table :rows rows :columns (etaf-value columns)
                    :row-key #'etaf-ui-cell-test--row-key)))
      (should-not (etaf-ui-cell-test--hosts buffer "etaf-table-cell"))
      (setf (etaf-value columns)
            (list (list :key :name :label "Name" :width 30 :cell factory)))
      (with-current-buffer buffer
        (dolist (word '("prefix" "host" "fragment"))
          (should (string-match-p word (buffer-string)))))
      (should (= 1 (length (etaf-ui-cell-test--hosts buffer "etaf-table-cell"))))
      (setf (etaf-value columns) '((:key :name :label "Name" :width 12)))
      (with-current-buffer buffer
        (should (string-match-p "Default" (buffer-string))))
      (should-not (etaf-ui-cell-test--hosts buffer "etaf-table-cell")))))

(ert-deftest etaf-ui-cell-factory-uses-consumer-context-without-author-scope ()
  "Ordinary factories consume Context directly and capture business refs only."
  (let* ((etaf-ui-cell-test--calls nil)
         (shared (etaf-ref 0))
         (source (etaf-data-memory-source '((:id 1)) :id-key :id))
         (controller (etaf-data-controller source :auto-load t)))
    (unwind-protect
        (etaf-ui-cell-test--with-buffer buffer
          (etaf-mount
           buffer
           (etaf-view
            (etaf-ui-cell-test-factory-author
             :shared shared :controller controller :secret "Author secret")))
          (setf (etaf-value shared) 7)
          (with-current-buffer buffer
            (should (string-match-p "Table:7" (buffer-string)))
            (should (string-match-p "Grid:7" (buffer-string))))
          (should
           (equal '("Grid" "Table")
                  (sort (delete-dups (mapcar #'car etaf-ui-cell-test--calls))
                        #'string<)))
          (dolist (call etaf-ui-cell-test--calls)
            (should-not (equal (nth 1 call) (list shared 'author-private-state)))
            (should-not (nth 2 call)))
          (let ((local (etaf-ui-cell-test--hosts buffer "cell-author-local"))
                (cells (etaf-ui-cell-test--hosts buffer "cell-factory-consumer")))
            ;; The author stylesheet is active, so its absence from cells is
            ;; evidence of ownership rather than an unloaded stylesheet.
            (should (= 1 (length local)))
            (should (eq 'bold (plist-get (cdar local) :font-weight)))
            (should (eq 'italic (plist-get (cdar local) :font-style)))
            (should (= 2 (length cells)))
            (should (equal '("blue" "red")
                           (sort (mapcar (lambda (cell)
                                           (plist-get (cdr cell) :color))
                                         cells)
                                 #'string<)))
            (dolist (cell cells)
              (should-not (eq 'bold (plist-get (cdr cell) :font-weight)))
              (should-not (eq 'italic (plist-get (cdr cell) :font-style))))))
      (etaf-data-stop controller))))

(ert-deftest etaf-ui-cell-factory-rejects-ref-and-watch-creation ()
  "A factory cannot allocate persistent state or subscriptions during render."
  (dolist (operation '(create-ref watch watch-effect))
    (let* ((source (etaf-ref 0))
           (calls 0)
           (columns
            (list
             (list :key :illegal :width 12
                   :cell
                   (lambda (_row)
                     (pcase operation
                       ('create-ref (etaf-ref 0))
                       ('watch
                        (etaf-watch source (lambda (&rest _) (cl-incf calls))
                                    :immediate t))
                       ('watch-effect
                        (etaf-watch-effect
                         (lambda () (etaf-value source) (cl-incf calls)))))
                     "Unreachable")))))
      (etaf-ui-cell-test--with-buffer buffer
        (let ((failure
               (should-error
                (etaf-mount
                 buffer
                 (etaf-view
                  (etaf-table :rows '((:id 1)) :columns columns
                              :row-key #'etaf-ui-cell-test--row-key)))
                :type 'etaf-render-side-effect-error)))
          (should (equal (cdr failure) (list operation))))
        (should-not (etaf-runtime-for-buffer buffer))
        (setf (etaf-value source) 1)
        (should (zerop calls))))))

(ert-deftest etaf-ui-cell-table-default-row-refs-are-instance-local ()
  "Two Tables omit row-ref while retaining distinct, callable row addresses."
  (let (pressed)
    (etaf-ui-cell-test--with-buffer buffer
      (etaf-mount
       buffer
       (etaf-view
        (column
         (etaf-table :columns '((:key :name :label "Name"))
                     :rows '((:id 1 :name "Left"))
                     :row-key #'etaf-ui-cell-test--row-key
                     :on-row-press (lambda (row) (push row pressed)))
         (etaf-table :columns '((:key :name :label "Name"))
                     :rows '((:id 1 :name "Right"))
                     :row-key #'etaf-ui-cell-test--row-key
                     :on-row-press (lambda (row) (push row pressed))))))
      (let ((hosts (etaf-ui-cell-test--hosts buffer "etaf-table-row")))
        (should (= 2 (length hosts)))
        (should-not (equal (caar hosts) (caadr hosts)))
        (dolist (host hosts)
          (etaf-dispatch-event (etaf-runtime-for-buffer buffer) (car host) 'press))
        (should (equal '("Left" "Right")
                       (sort (mapcar (lambda (row) (plist-get row :name))
                                     pressed)
                             #'string<)))))))

(ert-deftest etaf-ui-cell-table-default-row-ref-follows-key ()
  "An automatic row address survives reorder and reads the committed row."
  (let ((rows (etaf-ref '((:id 1 :name "Old") (:id 2 :name "Second"))))
        pressed)
    (etaf-ui-cell-test--with-buffer buffer
      (etaf-mount
       buffer
       (etaf-view
        (etaf-table :columns '((:key :name :width 12))
                    :rows (etaf-value rows)
                    :row-key #'etaf-ui-cell-test--row-key
                    :on-row-press (lambda (row) (setq pressed row)))))
      (let* ((hosts (etaf-ui-cell-test--hosts buffer "etaf-table-row"))
             (ref (car (cl-find 1 hosts
                                :key (lambda (host)
                                       (plist-get (cdr host) :key))))))
        (should ref)
        (setf (etaf-value rows) '((:id 2 :name "Second") (:id 1 :name "New")))
        (should (assoc ref (etaf-ui-cell-test--hosts buffer "etaf-table-row")))
        (etaf-dispatch-event (etaf-runtime-for-buffer buffer) ref 'press)
        (should (equal '(:id 1 :name "New") pressed))))))

(ert-deftest etaf-ui-cell-row-and-column-reorder-retain-state ()
  "Counter state follows row and column keys, with one cleanup on deletion."
  (let* ((etaf-ui-cell-test--states nil)
         (etaf-ui-cell-test--removed nil)
         (rows (etaf-ref '((:id 1) (:id 2))))
         (columns (etaf-ref (list (etaf-ui-cell-test--counter-column :a)
                                 (etaf-ui-cell-test--counter-column :b)))))
    (etaf-ui-cell-test--with-buffer buffer
      (etaf-mount
       buffer
       (etaf-view
        (etaf-table :columns (etaf-value columns) :rows (etaf-value rows)
                    :row-key #'etaf-ui-cell-test--row-key)))
      (should (= 4 (length etaf-ui-cell-test--states)))
      (let* ((state (assoc '(1 :a) etaf-ui-cell-test--states))
             (ref (nth 2 state)))
        (etaf-dispatch-event (etaf-runtime-for-buffer buffer) ref 'press)
        (setf (etaf-value columns) (reverse (etaf-value columns)))
        (setf (etaf-value rows) (reverse (etaf-value rows)))
        (should (= 4 (length etaf-ui-cell-test--states)))
        (should-not etaf-ui-cell-test--removed)
        (etaf-dispatch-event (etaf-runtime-for-buffer buffer) ref 'press)
        (should (= 2 (etaf-value (cadr state))))
        (with-current-buffer buffer
          (should (string-match-p "1::a:2" (buffer-string)))))
      (setf (etaf-value rows) '((:id 2)))
      (should (= 2 (length etaf-ui-cell-test--removed)))
      (should (member '(1 :a) etaf-ui-cell-test--removed))
      (should (member '(1 :b) etaf-ui-cell-test--removed)))))

(ert-deftest etaf-ui-cell-grid-reorders-without-remounting-cells ()
  "DataGrid uses the same retained custom cells while preserving row identity."
  (let* ((etaf-ui-cell-test--states nil)
         (etaf-ui-cell-test--removed nil)
         (source (etaf-data-memory-source '((:id 1) (:id 2)) :id-key :id))
         (controller (etaf-data-controller source :auto-load t))
         (columns (etaf-ref (list (etaf-ui-cell-test--counter-column :a)
                                 (etaf-ui-cell-test--counter-column :b)))))
    (unwind-protect
        (etaf-ui-cell-test--with-buffer buffer
          (etaf-mount
           buffer
           (etaf-view
            (etaf-data-grid :controller controller :columns (etaf-value columns)
                            :row-key #'etaf-ui-cell-test--row-key)))
          (let* ((state (assoc '(1 :a) etaf-ui-cell-test--states))
                 (ref (nth 2 state)))
            (etaf-dispatch-event (etaf-runtime-for-buffer buffer) ref 'press)
            (setf (etaf-value columns) (reverse (etaf-value columns)))
            (setf (etaf-value (etaf-data-items controller)) '((:id 2) (:id 1)))
            (should (= 4 (length etaf-ui-cell-test--states)))
            (should-not etaf-ui-cell-test--removed)
            (etaf-dispatch-event (etaf-runtime-for-buffer buffer) ref 'press)
            (should (= 2 (etaf-value (cadr state))))
            (with-current-buffer buffer
              (should (string-match-p "1::a:2" (buffer-string)))))
          (setf (etaf-value (etaf-data-items controller)) '((:id 2)))
          (should (= 2 (length etaf-ui-cell-test--removed))))
      (etaf-data-stop controller))))

(ert-deftest etaf-ui-cell-duplicate-field-migration-retains-distinct-state ()
  "Name and Uppercase read the same field but retain distinct column identities."
  (let* ((etaf-ui-cell-test--states nil)
         (etaf-ui-cell-test--removed nil)
         (rows (etaf-ref '((:id 1 :name "Ada") (:id 2 :name "Lin"))))
         (columns
          (etaf-ref
           (mapcar
            (lambda (entry)
              (let ((key (car entry)) (transform (cdr entry)))
                (list :key key :label (if (eq key :name) "Name" "Uppercase")
                      :width 24
                      :cell
                      (lambda (row)
                        (etaf-node 'etaf-ui-cell-test-counter
                                   (list :row row :field key
                                         :value (funcall transform
                                                         (plist-get row :name)))
                                   nil)))))
            '((:name . identity) (:name-upper . upcase))))))
    (etaf-ui-cell-test--with-buffer buffer
      (etaf-mount
       buffer
       (etaf-view
        (etaf-table :rows (etaf-value rows) :columns (etaf-value columns)
                    :row-key #'etaf-ui-cell-test--row-key)))
      (let* ((runtime (etaf-runtime-for-buffer buffer))
             (name (assoc '(1 :name) etaf-ui-cell-test--states))
             (upper (assoc '(1 :name-upper) etaf-ui-cell-test--states))
             (other-name (assoc '(2 :name) etaf-ui-cell-test--states))
             (other-upper (assoc '(2 :name-upper) etaf-ui-cell-test--states)))
        (should (= 4 (length etaf-ui-cell-test--states)))
        (should-not (eq (cadr name) (cadr upper)))
        (should-not (eq (nth 2 name) (nth 2 upper)))
        (etaf-dispatch-event runtime (nth 2 name) 'press)
        (etaf-dispatch-event runtime (nth 2 upper) 'press)
        (etaf-dispatch-event runtime (nth 2 upper) 'press)
        (setf (etaf-value rows) '((:id 2 :name "Lin") (:id 1 :name "Grace")))
        (setf (etaf-value columns) (reverse (etaf-value columns)))
        (should (= 4 (length etaf-ui-cell-test--states)))
        (should-not etaf-ui-cell-test--removed)
        (etaf-dispatch-event runtime (nth 2 name) 'press)
        (etaf-dispatch-event runtime (nth 2 upper) 'press)
        (should (= 2 (etaf-value (cadr name))))
        (should (= 3 (etaf-value (cadr upper))))
        (should (zerop (etaf-value (cadr other-name))))
        (should (zerop (etaf-value (cadr other-upper))))
        (with-current-buffer buffer
          (dolist (label '("1::name:2:Grace" "1::name-upper:3:GRACE"
                           "2::name:0:Lin" "2::name-upper:0:LIN"))
            (should (string-match-p (regexp-quote label) (buffer-string)))))))))

(ert-deftest etaf-ui-cell-insert-delete-failure-preserves-scopes-and-handlers ()
  "Failed replacement disposes only new cells and keeps retired candidates live."
  (let* ((etaf-ui-cell-test--states nil)
         (etaf-ui-cell-test--removed nil)
         (etaf-ui-cell-test--disposed nil)
         (etaf-ui-cell-test--mounted nil)
         (etaf-ui-cell-test--observed nil)
         (initial '((:id 1) (:id 2)))
         (rows (etaf-ref initial))
         (pulse (etaf-ref 0))
         (columns
          (list
           (list :key :action :width 12
                 :cell
                 (lambda (row)
                   (when (plist-get row :fail) (error "Reject replacement cell"))
                   (etaf-node 'etaf-ui-cell-test-resource
                              (list :row row :pulse pulse) nil))))))
    (etaf-ui-cell-test--with-buffer buffer
      (etaf-mount
       buffer
       (etaf-view
        (etaf-table :rows (etaf-value rows) :columns columns
                    :row-key #'etaf-ui-cell-test--row-key)))
      (let* ((runtime (etaf-runtime-for-buffer buffer))
             (first (assoc 1 etaf-ui-cell-test--states))
             (second (assoc 2 etaf-ui-cell-test--states))
             (first-ref (nth 2 first))
             (second-ref (nth 2 second)))
        (etaf-dispatch-event runtime first-ref 'press)
        (let ((generation (etaf-runtime-current-generation runtime))
              (text (with-current-buffer buffer (buffer-string))))
          ;; Row 3 has completed setup before row 2 rejects the candidate;
          ;; row 1 is absent from that same candidate and must not retire yet.
          (should-error
           (setf (etaf-value rows) '((:id 3) (:id 2 :fail t)))
           :type 'error)
          (should (eq generation (etaf-runtime-current-generation runtime)))
          (should (equal-including-properties
                   text (with-current-buffer buffer (buffer-string)))))
        (should (= 3 (length etaf-ui-cell-test--states)))
        (let ((failed-ref (nth 2 (assoc 3 etaf-ui-cell-test--states))))
          (should failed-ref)
          (should (equal (list failed-ref) etaf-ui-cell-test--disposed))
          (should-not (memq failed-ref etaf-ui-cell-test--mounted))
          (should-not etaf-ui-cell-test--removed)
          ;; Restore the business source before dispatch can legitimately
          ;; retry its still-invalid value at the ordinary batch boundary.
          (setf (etaf-value rows) initial)
          (should (= 3 (length etaf-ui-cell-test--states)))
          (etaf-dispatch-event runtime first-ref 'press)
          (etaf-dispatch-event runtime second-ref 'press)
          (should (= 2 (etaf-value (cadr first))))
          (should (= 1 (etaf-value (cadr second))))
          (setf (etaf-value pulse) 1)
          (should (= 2 (length etaf-ui-cell-test--observed)))
          (should (assoc first-ref etaf-ui-cell-test--observed))
          (should (assoc second-ref etaf-ui-cell-test--observed))
          (should-not (assoc failed-ref etaf-ui-cell-test--observed))
          (setf (etaf-value rows) '((:id 3) (:id 2)))
          (should (= 4 (length etaf-ui-cell-test--states)))
          (let ((new-ref (nth 2 (assoc 3 etaf-ui-cell-test--states))))
            (should-not (eq failed-ref new-ref))
            (should (equal (list first-ref) etaf-ui-cell-test--removed))
            (should (= 3 (length etaf-ui-cell-test--mounted)))
            (should (memq new-ref etaf-ui-cell-test--mounted))
            (setq etaf-ui-cell-test--observed nil)
            (setf (etaf-value pulse) 2)
            (should (= 2 (length etaf-ui-cell-test--observed)))
            (should (assoc second-ref etaf-ui-cell-test--observed))
            (should (assoc new-ref etaf-ui-cell-test--observed))
            (etaf-unmount runtime)
            (should (= 4 (length etaf-ui-cell-test--disposed)))
            (dolist (ref (list first-ref second-ref failed-ref new-ref))
              (should (= 1 (cl-count ref etaf-ui-cell-test--disposed))))
            (should (= 3 (length etaf-ui-cell-test--removed)))
            (dolist (ref (list first-ref second-ref new-ref))
              (should (= 1 (cl-count ref etaf-ui-cell-test--removed))))
            (setq etaf-ui-cell-test--observed nil)
            (setf (etaf-value pulse) 3)
            (should-not etaf-ui-cell-test--observed)))))))

(ert-deftest etaf-ui-cell-later-factory-error-retains-committed-handler ()
  "A failed later cell cannot replace an earlier cell's committed callback."
  (let* ((rows (etaf-ref '((:id 1 :name "Committed") (:id 2 :name "Later"))))
         (first-ref (make-symbol "etaf-cell-first"))
         pressed
         (columns
          (list
           (list :key :action :width 16
                 :cell
                 (lambda (row)
                   (when (plist-get row :fail) (error "Late cell failure"))
                   (let ((name (plist-get row :name)))
                     (etaf-node 'box
                                (list :ref (when (= 1 (plist-get row :id))
                                             first-ref)
                                      :on-press (lambda () (setq pressed name)))
                                (list name))))))))
    (etaf-ui-cell-test--with-buffer buffer
      (etaf-mount
       buffer
       (etaf-view
        (etaf-table :rows (etaf-value rows) :columns columns
                    :row-key #'etaf-ui-cell-test--row-key)))
      (let* ((runtime (etaf-runtime-for-buffer buffer))
             (generation (etaf-runtime-current-generation runtime))
             (text (with-current-buffer buffer (buffer-string))))
        (should-error
         (setf (etaf-value rows)
               '((:id 1 :name "Candidate") (:id 2 :name "Failure" :fail t))))
        (should (eq generation (etaf-runtime-current-generation runtime)))
        (should (equal-including-properties
                 text (with-current-buffer buffer (buffer-string))))
        (etaf-dispatch-event runtime first-ref 'press)
        (should (equal "Committed" pressed))
        (setf (etaf-value rows) '((:id 1 :name "Published") (:id 2)))
        (etaf-dispatch-event runtime first-ref 'press)
        (should (equal "Published" pressed))))))

(ert-deftest etaf-ui-cell-grid-content-update-stays-row-local ()
  "An item update evaluates one custom cell; selection visits only its delta."
  (let* ((etaf-ui-cell-test--calls nil)
         (rows (cl-loop for id from 1 to 12
                        collect (list :id id :name (format "Row %d" id))))
         (source (etaf-data-memory-source rows :id-key :id))
         (controller (etaf-data-controller source :page-size 12 :auto-load t))
         (columns '((:key :name :width 12 :cell etaf-ui-cell-test--name))))
    (unwind-protect
        (etaf-ui-cell-test--with-buffer buffer
          (etaf-mount
           buffer
           (etaf-view
            (etaf-data-grid :controller controller :columns columns
                            :row-key #'etaf-ui-cell-test--row-key)))
          (setq etaf-ui-cell-test--calls nil)
          (setf (etaf-value (etaf-data-items controller))
                (mapcar (lambda (row)
                          (if (= 6 (plist-get row :id))
                              '(:id 6 :name "Changed")
                            row))
                        rows))
          (should (equal '(6) etaf-ui-cell-test--calls))
          (etaf-data-select-one controller 1)
          (setq etaf-ui-cell-test--calls nil)
          (etaf-data-select-one controller 2)
          (should (cl-every (lambda (id) (memq id '(1 2)))
                            etaf-ui-cell-test--calls))
          (should (<= (length etaf-ui-cell-test--calls) 2)))
      (etaf-data-stop controller))))

(ert-deftest etaf-ui-cell-button-owns-clipped-row-interaction ()
  "A clipped official Button owns its hit area even while disabled."
  (let* ((disabled (etaf-ref t))
         (button-ref (make-symbol "etaf-clipped-cell-button"))
         (button-presses 0)
         (row-presses 0)
         (columns
          (list '(:key :name :label "Name" :width 8)
                (list :key :action :label "Action" :width 5
                      :cell (lambda (_row)
                              (etaf-node
                               'etaf-button
                               (list :label "ABCDEFGHIJK" :ref button-ref
                                     :disabled (etaf-value disabled)
                                     :on-press (lambda () (cl-incf button-presses)))
                               nil)))
                '(:key :tail :label "Tail" :width 6))))
    (etaf-ui-cell-test--with-buffer buffer
      (etaf-mount
       buffer
       (etaf-view
        (etaf-table :columns columns :rows '((:id 1 :name "ITEM" :tail "TAIL"))
                    :row-key #'etaf-ui-cell-test--row-key
                    :on-row-press (lambda (_row) (cl-incf row-presses)))))
      (let* ((runtime (etaf-runtime-for-buffer buffer))
             (cell-ref
              (car (cl-find :action
                            (etaf-ui-cell-test--hosts buffer "etaf-table-cell")
                            :key (lambda (host) (plist-get (cdr host) :key))))))
        (should cell-ref)
        (let ((button-bounds (ebox-host-ref-bounds buffer button-ref))
              (cell-bounds (ebox-host-ref-bounds buffer cell-ref)))
          (should button-bounds)
          (should (<= (car cell-bounds) (car button-bounds)))
          (should (<= (cdr button-bounds) (cdr cell-bounds))))
        (with-current-buffer buffer
          (goto-char (etaf-host-ref-position runtime button-ref))
          (should-error (etaf-activate runtime) :type 'user-error))
        (should-error (etaf-dispatch-event runtime button-ref 'press)
                      :type 'etaf-event-error)
        (should (zerop button-presses))
        (should (zerop row-presses))
        (setf (etaf-value disabled) nil)
        (with-current-buffer buffer
          (goto-char (etaf-host-ref-position runtime button-ref))
          (etaf-activate runtime))
        (should (= 1 button-presses))
        (should (zerop row-presses))
        (with-current-buffer buffer
          (goto-char (point-min))
          (search-forward "ITEM")
          (backward-char)
          (etaf-activate runtime)
          (should (search-forward "TAIL" nil t)))
        (should (= 1 row-presses))))))

(provide 'etaf-ui-cell-tests)
;;; etaf-ui-cell-tests.el ends here
