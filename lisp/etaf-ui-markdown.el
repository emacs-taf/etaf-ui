;;; etaf-ui-markdown.el --- Markdown document rendering for etaf-ui -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: GPL-3.0-or-later

;;; Commentary:
;;
;; Markdown document rendering shared by ETAF applications.  The functions
;; turn the block tree of `etaf-ui-markdown-parse' into ordinary ETAF Views:
;; headings, paragraphs, lists, blockquote callouts, pipe tables, fenced code
;; blocks, footnotes and inline emphasis, code, links and media placeholders.
;; Presentation is data-driven: every color comes from the caller's `:palette'
;; alist, and media and code blocks go through caller callbacks, so one
;; renderer serves a previewer, a manual reader or any other document view.
;;
;; The renderer owns no state and no buffer; it is a pure function of a block
;; tree plus an environment plist, which makes it usable for headless tests and
;; inside a mounted Component alike.  See `etaf-ui-markdown-view-block' and
;; `etaf-ui-markdown-view-blocks' for the environment contract.

;;; Code:

(require 'cl-lib)
(require 'subr-x)
(require 'etaf)
(require 'etaf-ui-basic)
(require 'etaf-ui-feedback)
(require 'etaf-ui-markdown-parse)


;;; ---------------------------------------------------------------------------

(defun etaf-ui-markdown--env-color (env key)
  "Return ENV's color for semantic KEY.
ENV carries a `:palette' alist of semantic color keys; a missing palette or an
unknown key signals `etaf-ui-markdown-error'."
  (let ((palette (plist-get env :palette)))
    (unless palette
      (signal 'etaf-ui-markdown-error
              (list "Markdown rendering requires a :palette")))
    (or (cdr (assq key palette))
        (signal 'etaf-ui-markdown-error
                (list (format "Unknown markdown color: %S" key))))))

(defun etaf-ui-markdown--env-color-or (env key fallback-key)
  "Return ENV's color for KEY, or its FALLBACK-KEY when KEY is absent.
A palette may leave an optional key out; the fallback keeps the renderer from
requiring every palette to name a color it never wanted to choose."
  (let ((palette (plist-get env :palette)))
    (or (and palette (cdr (assq key palette)))
        (etaf-ui-markdown--env-color env fallback-key))))

(defun etaf-ui-markdown--mono-family ()
  "Return the family of the frame's fixed-pitch font, or nil.
A frame whose fixed-pitch face inherits the default family yields nil, and
code spans then use the frame's own font instead of guessing a family."
  (let ((family (face-attribute 'fixed-pitch :family nil t)))
    (and (stringp family) (not (string-empty-p family)) family)))

(defun etaf-ui-markdown--base-pixels ()
  "Return the frame's default font size in CSS reference pixels."
  (let ((height (face-attribute 'default :height nil t)))
    (if (numberp height)
        (max 8 (round (/ (* height 4.0) 30.0)))
      16.0)))

(defun etaf-ui-markdown--heading-pixels (level)
  "Return the heading font size for LEVEL."
  (let ((base (etaf-ui-markdown--base-pixels)))
    (round (pcase level
             (1 (* base 1.42))
             (2 (* base 1.26))
             (3 (* base 1.10))
             (_ base)))))

(defun etaf-ui-markdown--divider (&optional label)
  "Return a horizontal divider View, optionally labeled."
  (etaf-node 'etaf-divider (list :orientation 'horizontal :label label) nil))

(defun etaf-ui-markdown--spacer (&optional lines)
  "Return an empty spacer Box LINES lines tall."
  (etaf-node 'box (list :height (list 'lh (or lines 1))) nil))


(defun etaf-ui-markdown--code-color (env)
  "Return ENV's background for code surfaces.
The palette may provide `:code-bg'; without it code uses `:panel'."
  (etaf-ui-markdown--env-color
   env (if (assq :code-bg (plist-get env :palette)) :code-bg :panel)))

(defun etaf-ui-markdown--run-props (run env)
  "Return the ETAF style props of inline RUN in ENV."
  (let ((props nil))
    (when (plist-get run :bold)
      (setq props (plist-put props :font-weight 'bold)))
    (when (plist-get run :italic)
      (setq props (plist-put props :font-style 'italic)))
    (when (plist-get run :strike)
      (setq props (plist-put props :text-decoration-line '(line-through))))
    (when (plist-get run :code)
      (setq props (plist-put props :background-color
                             (etaf-ui-markdown--code-color env)))
      (let ((mono (etaf-ui-markdown--mono-family)))
        (when mono (setq props (plist-put props :font-family mono)))))
    (when (plist-get run :link)
      (setq props (plist-put props :color (etaf-ui-markdown--env-color env :accent)))
      (setq props (plist-put props :text-decoration-line '(underline))))
    (when (plist-get run :muted)
      (setq props (plist-put props :color (etaf-ui-markdown--env-color env :muted))))
    props))

(defun etaf-ui-markdown--flatten-inlines (nodes inherited env)
  "Return styled run entries for inline NODES in ENV.
INHERITED is the style attribute plist of the enclosing inline element.
Entries are (:text STRING :props PLIST) or (:view VIEW)."
  (let (result)
    (dolist (node nodes)
      (pcase (plist-get node :type)
        ('text
         (push (list :text (or (plist-get node :text) "") :props inherited) result))
        ('break
         (push (list :text (if (plist-get node :hard) "\n" " ") :props inherited)
               result))
        ('code
         (push (list :text (or (plist-get node :text) "")
                     :props (plist-put (copy-sequence inherited) :code t))
               result))
        ((or 'emph 'strong 'strike)
         (let ((child (copy-sequence inherited)))
           (when (eq (plist-get node :type) 'emph)
             (setq child (plist-put child :italic t)))
           (when (eq (plist-get node :type) 'strong)
             (setq child (plist-put child :bold t)))
           (when (eq (plist-get node :type) 'strike)
             (setq child (plist-put child :strike t)))
           (setq result
                 (append (nreverse
                          (etaf-ui-markdown--flatten-inlines
                           (plist-get node :children) child env))
                         result))))
        ((or 'link 'autolink)
         (let ((child (plist-put (copy-sequence inherited) :link (plist-get node :url))))
           (setq result
                 (append (nreverse
                          (etaf-ui-markdown--flatten-inlines
                           (plist-get node :children) child env))
                         result))))
        ('footnote-ref
         (push (list :view (etaf-ui-markdown--footnote-view node env)) result))
        ('image
         (push (list :view (etaf-ui-markdown--render-media 'inline-image node env))
               result))
        ('html
         (push (list :text (or (plist-get node :text) "")
                     :props (plist-put (copy-sequence inherited) :muted t))
               result))
        (_ nil)))
    (nreverse result)))

(defun etaf-ui-markdown--inline-runs (inlines env base)
  "Flatten INLINES into styled runs for ENV.
BASE is the plist of style attributes inherited from the enclosing block.
Adjacent text runs with equal styles are merged into one entry."
  (let ((runs nil))
    (dolist (run (etaf-ui-markdown--flatten-inlines inlines base env))
      (let* ((previous (car runs))
             (text (plist-get run :text))
             (props (plist-get run :props))
             (merge (and previous
                         (not (plist-get previous :view))
                         (not (plist-get run :view))
                         (plist-get previous :text)
                         (equal (plist-get previous :props) props)
                         (not (string-suffix-p "\n" (plist-get previous :text)))
                         (not (string-prefix-p "\n" text)))))
        (if merge
            (setcar runs (plist-put previous :text
                                    (concat (plist-get previous :text) text)))
          (push run runs))))
    (nreverse runs)))

(defun etaf-ui-markdown--render-media (kind node env)
  "Render media NODE of KIND through ENV's `:render-media', or a placeholder.
KIND is `image' for a block image, `video' for a block video, `inline-image'
for an inline image and `html-media' for a source-bearing HTML media element.
NODE is the parsed inline or a media descriptor.  Without `:render-media' the
renderer keeps the document text: the media's alt text or URL."
  (if-let* ((renderer (plist-get env :render-media)))
      (funcall renderer kind node env)
    (etaf-node 'text
               (list :color (etaf-ui-markdown--env-color env :muted))
               (list (format "[%s]" (or (plist-get node :alt)
                                         (plist-get node :url)
                                         "media"))))))

(defun etaf-ui-markdown--code-link (run env)
  "Return (URL . HELP) when code RUN links through ENV, or nil.
ENV's `:code-link' is called with the code text; it may return a URL string
or a (URL . HELP) cons.  Only code spans are asked."
  (when-let* ((callback (plist-get env :code-link))
              (text (plist-get run :text))
              ((plist-get (plist-get run :props) :code)))
    (let ((link (funcall callback text)))
      (cond ((stringp link) (cons link link))
            ((and (consp link) (stringp (car link))) link)
            (t nil)))))

(defun etaf-ui-markdown--runs-view (inlines env base &optional extra)
  "Return ETAF children for INLINES in ENV.
BASE is a run-attribute plist (`:bold', `:italic', `:strike', `:code',
`:link', `:muted'); EXTRA is an Ebox style plist applied to every text run."
  (let ((nodes nil))
    (dolist (run (etaf-ui-markdown--inline-runs inlines env base))
      (if-let* ((view (plist-get run :view)))
          (push view nodes)
        (let* ((attributes (plist-get run :props))
               (text (plist-get run :text))
               (code-link (etaf-ui-markdown--code-link run env))
               (props (let ((merged (copy-sequence extra))
                            (inline (etaf-ui-markdown--run-props attributes env)))
                        ;; Heading typography supplies defaults; an inline
                        ;; link or code span overrides only its own properties.
                        (while inline
                          (setq merged (plist-put merged (pop inline) (pop inline))))
                        merged))
               (url (or (plist-get attributes :link) (car code-link)))
               (help (or (cdr code-link) url))
               (open (plist-get env :open-link))
               (props (if url
                          (let ((result (append props
                                                (list :role 'link :tab-index 0 :help-echo help
                                                      :hover-style
                                                      (list :background-color
                                                            (etaf-ui-markdown--env-color
                                                             env :accent-soft))))))
                            ;; A code link may share a span with its own text
                            ;; decoration; a second entry would be a duplicate
                            ;; View property.
                            (when code-link
                              (setq result (plist-put
                                            result :text-decoration-line '(underline))))
                            (append result
                                    (list :on-press (when open
                                                      (lambda () (funcall open url))))))
                        props)))
          (push (etaf-node 'text props (list text)) nodes))))
    (nreverse nodes)))

(defun etaf-ui-markdown--footnote-view (node env)
  "Return the superscript reference View of footnote NODE in ENV."
  (let ((number (or (plist-get node :number)
                    (plist-get node :label)))
        (label (plist-get node :label)))
    (etaf-node 'text
               (append
                (list :color (etaf-ui-markdown--env-color env :accent))
                (unless (plist-get env :line-grid)
                  (list :font-size (round (* (etaf-ui-markdown--base-pixels) 0.8))))
                (list :role 'link :tab-index 0
                     :help-echo (format "Footnote %s" label)
                     :on-press (lambda ()
                                 (when-let* ((jump (plist-get env :footnote-jump)))
                                   (funcall jump label)))))
               (list (format "[%s]" number)))))

(defun etaf-ui-markdown--paragraph-node (block env)
  "Return the paragraph View of BLOCK in ENV.
A paragraph that contains only one image delegates to ENV's `:render-media'."
  (if (and (= 1 (length (plist-get block :children)))
           (eq (plist-get (car (plist-get block :children)) :type) 'image))
      (let ((image (car (plist-get block :children))))
        (etaf-ui-markdown--render-media 'image image env))
    (etaf-node 'box
               (list :width 'stretch :wrap-mode 'word)
               (etaf-ui-markdown--runs-view (plist-get block :children) env nil))))

(defun etaf-ui-markdown--heading-node (block env)
  "Return the heading View of BLOCK in ENV.
With ENV's `:line-grid' the heading keeps the body font size, so its line
has the standard height; the level then shows through color and, for level
2, an accent bar drawn as a left border that occupies no line.  Without
`:line-grid' the top two levels draw a rule from `:heading-rule' under the
text, which sets the level apart even in a theme whose heading color is its
body color."
  (let* ((level (plist-get block :level))
         (grid (plist-get env :line-grid))
         (color (cond ((>= level 5) (etaf-ui-markdown--env-color env :muted))
                      ((and grid (= level 1))
                       (etaf-ui-markdown--env-color env :accent))
                      (t (etaf-ui-markdown--env-color env :heading))))
         (children
          (etaf-ui-markdown--runs-view
           (plist-get block :children) env (list :bold t)
           (append (unless grid
                     (list :font-size (etaf-ui-markdown--heading-pixels level)))
                   (list :color color)))))
    (etaf-node 'box
               (append
                (list :id (plist-get block :id)
                      :width 'stretch
                      ;; The block flow separates every sibling with exactly
                      ;; one blank line, including heading-to-heading, so a
                      ;; heading carries no margin of its own.
                      :margin '((lh 0) (ch 0)))
                (when (and grid (= level 2))
                  (list :border-left
                        (list '(px 3) 'solid
                              (etaf-ui-markdown--env-color env :accent))
                        :padding-left '(ch 1)))
                (when (and (not grid) (<= level 2))
                  (list :border-bottom
                        (list '(px 1) 'solid
                              (etaf-ui-markdown--env-color-or
                               env :heading-rule :border))
                        :padding-bottom '(lh 0.35))))
               children)))

(defun etaf-ui-markdown--code-block-node (block env)
  "Return the code block View of BLOCK in ENV.
ENV's `:render-code-block', when present, may return a View for the block;
nil keeps the default fenced block."
  (or (when-let* ((renderer (plist-get env :render-code-block)))
        (funcall renderer block env))
      (etaf-ui-markdown--default-code-block-node block env)))

(defun etaf-ui-markdown--default-code-block-node (block env)
  "Return the default fenced code block View of BLOCK in ENV.
A block with a language opens with a header strip: the language sits on its
own row, a rule closes it, and the code starts under that rule, so the label
frames the block instead of floating over its first line."
  (let* ((mono (etaf-ui-markdown--mono-family))
         (lang (plist-get block :lang))
         (border (etaf-ui-markdown--env-color env :border))
         (body (etaf-node 'box
                          (list :width 'stretch :wrap-mode 'char
                                :font-family mono
                                :padding (if lang '((lh 0.5) (ch 2))
                                           '((lh 1) (ch 2)))
                                :color (etaf-ui-markdown--env-color env :ink))
                          (list (etaf-node 'text nil
                                           (list (plist-get block :text))))))
         (header (when lang
                   (etaf-node 'box
                              (list :width 'stretch
                                    :border-bottom (list '(px 1) 'solid border)
                                    :padding '((lh 0) (ch 2)))
                              (list (etaf-node 'text
                                               (list :font-family mono
                                                     :color (etaf-ui-markdown--env-color
                                                             env :muted))
                                               (list lang)))))))
    (etaf-node 'box
               (list :width 'stretch
                     :background-color (etaf-ui-markdown--code-color env)
                     :border (list '(px 1) 'solid border))
               (append (when header (list header)) (list body)))))

(defun etaf-ui-markdown--blockquote-node (block env)
  "Return the blockquote View of BLOCK in ENV.
A GitHub alert (`> [!NOTE]' and friends) becomes a tinted callout; any other
quote keeps the muted surface and the accent bar."
  (let* ((children (plist-get block :children))
         (alert (and (plist-get (plist-get env :features) :alerts)
                     (etaf-ui-markdown--alert-kind children env))))
    (if alert
        (let* ((spec (etaf-ui-markdown--alert-spec alert env))
               (color (etaf-ui-markdown--env-color env (nth 1 spec)))
               (soft (etaf-ui-markdown--env-color env (nth 2 spec))))
          (etaf-node 'box
                     (list :width 'stretch
                           :background-color soft
                           :border-left (list '(px 3) 'solid color)
                           :padding-top '(lh 0)
                           :padding-bottom '(lh 0)
                           :padding-left '(ch 2)
                           :padding-right '(ch 2))
                     (append
                      (list (etaf-node 'text
                                       (list :color color :font-weight 'bold)
                                       (list (format "%s %s" (nth 3 spec) (nth 0 spec)))))
                      (etaf-ui-markdown-view-blocks
                       (etaf-ui-markdown--alert-blocks children) env t))))
      (etaf-node 'box
                 (list :width 'stretch
                       :background-color (etaf-ui-markdown--env-color env :quote-bg)
                       :border-left (list '(px 3) 'solid
                                          (etaf-ui-markdown--env-color env :quote-bar))
                       ;; A quote recedes behind its own surface: its plain
                       ;; text takes the muted color, while a link and a code
                       ;; span keep the colors they set for themselves.
                       :color (etaf-ui-markdown--env-color env :muted)
                       :padding-top '(lh 0)
                       :padding-bottom '(lh 0)
                       :padding-left '(ch 2)
                       :padding-right '(ch 2))
                 (etaf-ui-markdown-view-blocks children env t)))))

(defun etaf-ui-markdown--alert-kind (blocks env)
  "Return the GitHub alert kind when BLOCKS open with an alert marker."
  (let* ((first (car blocks))
         (children (and first (eq (plist-get first :type) 'paragraph)
                        (plist-get first :children)))
         (text (and children (eq (plist-get (car children) :type) 'text)
                    (plist-get (car children) :text))))
    (when (and text (string-match "\\`\\[!\\([A-Za-z]+\\)\\][ \t]*\\(?:\n\\|\\'\\)" text))
      (let ((kind (downcase (match-string 1 text))))
        (and (etaf-ui-markdown--alert-spec kind env) kind)))))
(defconst etaf-ui-markdown--alert-defaults
  '((note "Note" :accent :accent-soft "ℹ")
    (tip "Tip" :ok :ok-soft "✔")
    (important "Important" :important :important-soft "★")
    (warning "Warning" :warn :warn-soft "⚠")
    (caution "Caution" :danger :danger-soft "⛔"))
  "GitHub alert kinds with their default label, color keys and icon.")

(defun etaf-ui-markdown--alert-spec (kind env)
  "Return (LABEL COLOR-KEY SOFT-KEY ICON) for alert KIND in ENV, or nil.
ENV's `:alert-labels' alist may override the labels of
`etaf-ui-markdown--alert-defaults'."
  (let* ((name (intern (downcase kind)))
         (spec (cdr (assq name etaf-ui-markdown--alert-defaults))))
    (when spec
      (if-let* ((label (cdr (assq name (plist-get env :alert-labels)))))
          (cons label (cdr spec))
        spec))))

(defun etaf-ui-markdown--alert-blocks (blocks)
  "Return BLOCKS with the leading alert marker removed.
The document tree is shared across renders, so the first paragraph is rebuilt
instead of mutated."
  (let* ((first (car blocks))
         (children (plist-get first :children))
         (text (plist-get (car children) :text))
         (rest (replace-regexp-in-string
                "\\`\\[![A-Za-z]+\\][ \t]*\\n?" "" text)))
    (cons (let ((paragraph (copy-sequence first)))
            (plist-put paragraph :children
                       (if (string-empty-p rest)
                           (cdr children)
                         (cons (plist-put (copy-sequence (car children)) :text rest)
                               (cdr children)))))
          (cdr blocks))))

(defun etaf-ui-markdown--inline-width (inlines)
  "Return the display width of the text of INLINES and their children."
  (let ((width 0))
    (dolist (node inlines)
      (setq width (+ width
                     (string-width (or (plist-get node :text) ""))
                     (etaf-ui-markdown--inline-width
                      (plist-get node :children)))))
    width))

(defconst etaf-ui-markdown--cell-min-width 12
  "Cap, in character cells, of a wide-character token's table floor.
A line may break between wide characters, so a long CJK sentence does not
force a wide column.  A narrow token has no such break opportunity, so it
keeps its full width instead.")

(defconst etaf-ui-markdown--cell-max-floor 32
  "Cap, in character cells, of one table column's unbreakable floor.")

(defun etaf-ui-markdown--token-width (token)
  "Return the floor TOKEN asks of its table column."
  (let ((width (string-width token))
        (wide (cl-some (lambda (char) (>= (char-width char) 2))
                       (string-to-list token))))
    (if wide (min etaf-ui-markdown--cell-min-width width) width)))

(defun etaf-ui-markdown--inline-segments (inlines)
  "Return the unbreakable widths of the text of INLINES and their children."
  (let ((widths nil))
    (dolist (node inlines)
      (dolist (token (split-string (or (plist-get node :text) "")
                                   "[ \t\n]+" t))
        (push (etaf-ui-markdown--token-width token) widths))
      (setq widths (append (etaf-ui-markdown--inline-segments
                            (plist-get node :children))
                           widths)))
    widths))

(defun etaf-ui-markdown--table-floors (rows columns)
  "Return the min-width floors of COLUMNS for table ROWS.
A column's floor covers its widest unbreakable token plus the cell's padding
and hairline borders, so a word or a short CJK run stays whole.  Every row
gets the same floor for a column: the table is one grid, so a floor taken
from a single row would resolve that row's tracks against other widths and
push it out of line."
  (let ((widths (make-list columns 0)))
    (dolist (row rows)
      (cl-loop for inlines in row
               for column from 0
               do (setf (nth column widths)
                        (max (nth column widths)
                             (apply #'max 0
                                    (etaf-ui-markdown--inline-segments inlines))))))
    (mapcar (lambda (width)
              (+ 4 (min etaf-ui-markdown--cell-max-floor (or width 0))))
            widths)))

(defun etaf-ui-markdown--table-tracks (floors weights)
  "Return the grid tracks of a table from FLOORS and content WEIGHTS.
Each column keeps its floor, so its words stay whole, and shares the space
above the floors in proportion to its widest cell, bounded so one long
column cannot starve the others."
  (cl-loop for floor in floors
           for weight in weights
           collect (list 'minmax (list 'ch floor)
                         (list 'fr (max 4 (min 32 weight))))))

(defun etaf-ui-markdown--table-stripe (env)
  "Return the body-row stripe surface of a table in ENV, or nil.
A palette whose stripe and header row are the same surface gets no stripes:
painting a row the color it already has costs a paint and shows nothing."
  (let ((stripe (etaf-ui-markdown--env-color env :table-stripe))
        (header (etaf-ui-markdown--env-color env :table-header)))
    (unless (equal stripe header) stripe)))

(defun etaf-ui-markdown--table-node (block env)
  "Return the table View of BLOCK in ENV.
The table draws its own grid: an outer border, a row separator, a column
separator, a tinted header row and zebra striping, so every column and
alignment stays visible at a glance.  Columns share the width in proportion
to their content and never go narrower than their widest unbreakable token
plus the cell padding, and cells wrap at word boundaries.

The whole table is one grid, and its floors are the column maximums over
every row.  A grid per row gave each row its own track resolution, so a row
whose cells measured differently resolved the same `fr' tracks to other
widths and drifted out of line with its neighbours; the grid's own minimum
keeps a tight container from squeezing cells below their words."
  (let* ((aligns (plist-get block :aligns))
         (columns (length aligns))
         (rows (append (list (plist-get block :header))
                       (plist-get block :rows)))
         (floors (etaf-ui-markdown--table-floors rows columns))
         (weights (cl-loop for column below columns
                           collect (cl-loop for row in rows
                                            maximize (etaf-ui-markdown--inline-width
                                                      (nth column row)))))
         (tracks (etaf-ui-markdown--table-tracks floors weights))
         (last-row (1- (length rows)))
         (border (list '(px 1) 'solid (etaf-ui-markdown--env-color env :border)))
         ;; Ebox draws top and bottom borders at one pixel, so the header
         ;; rule is set apart by color instead of width.
         (header-rule (list '(px 1) 'solid
                            (etaf-ui--color-mix
                             (etaf-ui-markdown--env-color env :border)
                             (etaf-ui-markdown--env-color env :ink) 0.35)))
         (stripe (etaf-ui-markdown--table-stripe env))
         (cells nil))
    (cl-loop for row in rows
             for row-index from 0
             do (cl-loop for inlines in row
                         for align in aligns
                         for column-index from 0
                         do (push
                             (etaf-node 'box
                                        (list :padding '((lh 0) (ch 1))
                                              :min-width (list 'ch (nth column-index floors))
                                              :width 'stretch
                                              :overflow 'hidden
                                              :wrap-mode 'word
                                              :text-align (or align 'left)
                                              :border-bottom
                                              (cond ((zerop row-index) header-rule)
                                                    ((/= row-index last-row) border))
                                              :background-color
                                              (cond
                                               ((zerop row-index)
                                                (etaf-ui-markdown--env-color env :table-header))
                                               ((and stripe (zerop (% row-index 2)))
                                                stripe)
                                               (t nil)))
                                        (etaf-ui-markdown--runs-view
                                         inlines env
                                         (when (zerop row-index) (list :bold t))))
                             cells)))
    (etaf-node 'box
               (list :width 'stretch
                     :min-width (list 'ch (+ 2 (apply #'+ floors)))
                     :border border)
               (list (etaf-node 'grid
                                (list :width 'stretch
                                      :grid-template-columns tracks)
                                (nreverse cells))))))

(defun etaf-ui-markdown--thematic-break-node ()
  "Return the thematic break View."
  (etaf-ui-markdown--divider))

(defconst etaf-ui-markdown--html-media-regexp
  "<\\(video\\|img\\)\\b[^>]*>"
  "Opening tags whose source is rendered as a media card.")

(defun etaf-ui-markdown--html-attribute (tag name)
  "Return NAME's attribute value from TAG, or nil."
  (when (string-match (format "%s[ \t]*=[ \t]*[\"']\\([^\"']*\\)[\"']" name) tag)
    (match-string 1 tag)))

(defun etaf-ui-markdown--html-comment-p (text)
  "Return non-nil when TEXT is an HTML comment block.
Comments carry no rendered content, so the renderer drops them instead of
printing markup the document never intended to show."
  (string-prefix-p "<!--" (string-trim text)))

(defun etaf-ui-markdown--html-media (text)
  "Return a media descriptor for raw HTML TEXT, or nil.
A `<video>' or `<img>' opening tag with a source becomes a descriptor with
`:url', `:kind' (`video' or `image') and `:alt'."
  (when (string-match etaf-ui-markdown--html-media-regexp text)
    (let* ((tag (match-string 0 text))
           (src (etaf-ui-markdown--html-attribute tag "src")))
      (when src
        (list :type 'html-media
              :url src
              :kind (if (string-match-p "\\`<video" tag) 'video 'image)
              :alt (or (etaf-ui-markdown--html-attribute tag "alt")
                       (etaf-ui-markdown--html-attribute tag "title")))))))

(defun etaf-ui-markdown--html-block-node (block env)
  "Return the View of raw HTML BLOCK in ENV, or nil.
HTML comments render as nothing; a media element goes through ENV's
`:render-media'; other tags stay visible as code, so the renderer never
silently drops content it cannot render."
  (let* ((text (plist-get block :text))
         (media (and (not (etaf-ui-markdown--html-comment-p text))
                     (etaf-ui-markdown--html-media text))))
    (cond
     ((etaf-ui-markdown--html-comment-p text) nil)
     (media (etaf-ui-markdown--render-media (plist-get media :kind) media env))
     (t (etaf-ui-markdown--html-code-node text env)))))

(defun etaf-ui-markdown--html-code-node (text env)
  "Return a muted monospace block View for raw HTML TEXT in ENV."
  (etaf-node 'box
             (list :width 'stretch :wrap-mode 'char
                   :background-color (etaf-ui-markdown--env-color env :panel)
                   :padding-top '(lh 1)
                   :padding-bottom '(lh 1)
                   :padding-left '(ch 2)
                   :padding-right '(ch 2))
             (list (etaf-node 'text
                              (list :color (etaf-ui-markdown--env-color env :muted))
                              (list text)))))

(defun etaf-ui-markdown--list-node (block env)
  "Return the list View of BLOCK in ENV."
  (let ((tight (plist-get block :tight))
        (ordered (plist-get block :ordered))
        (start (or (plist-get block :start) 1))
        (index 0)
        (items nil))
    (dolist (item (plist-get block :items))
      (cl-incf index)
      (let* ((checked (plist-get item :checked))
             (task (plist-get item :task))
             (marker
              (cond
               (task (etaf-node 'text
                                (list :color (if checked
                                                 (etaf-ui-markdown--env-color env :accent)
                                               (etaf-ui-markdown--env-color env :muted)))
                                (list (if checked "☑" "☐"))))
               (ordered (etaf-node 'text
                                   (list :color (etaf-ui-markdown--env-color env :muted))
                                   (list (format "%d." (+ start (1- index))))))
               (t (etaf-node 'text
                             (list :color (etaf-ui-markdown--env-color env :muted))
                             (list "•")))))
             (content (etaf-ui-markdown-view-blocks (plist-get item :children) env tight)))
        (push (etaf-node 'flex
                         (list :width 'stretch)
                         (list
                          (etaf-node 'box
                                     (list :width '(ch 3) :flex-shrink 0)
                                     (list marker))
                          (etaf-node 'column
                                     (list :width 'stretch :min-width '(ch 0))
                                     content)))
              items)))
    (etaf-node 'column
               (list :width 'stretch
                     :item-gap (list 'lh (if tight 0 1)))
               (nreverse items))))

(defun etaf-ui-markdown--footnote-def-node (block env)
  "Return the footnote definition View of BLOCK in ENV."
  (etaf-node 'box
             (list :width 'stretch :wrap-mode 'word
                   :id (format "footnote-%s" (plist-get block :label)))
             (append
              (list (etaf-node 'text
                               (list :color (etaf-ui-markdown--env-color env :accent)
                                     :font-weight 'bold)
                               (list (format "[%s] " (plist-get block :number)))))
              (etaf-ui-markdown--runs-view
               (cl-loop for child in (plist-get block :children)
                        append (if (eq (plist-get child :type) 'paragraph)
                                   (plist-get child :children)
                                 nil))
               env nil))))

(defun etaf-ui-markdown--view-block (block env)
  "Return the list of Views for one BLOCK in ENV."
  (pcase (plist-get block :type)
    ('heading (list (etaf-ui-markdown--heading-node block env)))
    ('paragraph (list (etaf-ui-markdown--paragraph-node block env)))
    ('code-block (list (etaf-ui-markdown--code-block-node block env)))
    ('blockquote (list (etaf-ui-markdown--blockquote-node block env)))
    ('list (list (etaf-ui-markdown--list-node block env)))
    ('table (list (etaf-ui-markdown--table-node block env)))
    ('thematic-break (list (etaf-ui-markdown--thematic-break-node)))
    ('html-block
     (when-let* ((node (etaf-ui-markdown--html-block-node block env)))
       (list node)))
    ('footnote-def (list (etaf-ui-markdown--footnote-def-node block env)))
    (_ nil)))

(defun etaf-ui-markdown-view-block (block env)
  "Return BLOCK rendered as one ETAF View, or nil when nothing renders.
A block that expands to several Views is wrapped in one column, so callers
own one node per block for references, spacing or scrolling."
  (let ((views (etaf-ui-markdown--view-block block env)))
    (cond
     ((null views) nil)
     ((null (cdr views)) (car views))
     (t (etaf-node 'column (list :width 'stretch :item-gap '(lh 0)) views)))))

(defun etaf-ui-markdown-view-blocks (blocks env &optional tight)
  "Return the list of Views for BLOCKS in ENV, in document order.
Every block is rendered by `etaf-ui-markdown--view-block'; consecutive blocks
are separated by one blank line, unless TIGHT drops it for nested content.
The list preserves the document order, so callers may wrap each View in their
own container for scrolling, selection or per-block references."
  (let ((nodes nil)
        (first t))
    (dolist (block blocks)
      (when-let* ((views (etaf-ui-markdown--view-block block env)))
        (unless (or first tight)
          (push (etaf-ui-markdown--spacer) nodes))
        (setq first nil)
        (dolist (view views)
          (when view (push view nodes)))))
    (nreverse nodes)))

(provide 'etaf-ui-markdown)
;;; etaf-ui-markdown.el ends here
