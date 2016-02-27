{-# OPTIONS_GHC -fno-warn-missing-signatures #-}

module X_2_1_Prop_Syntax where

import qualified Test.HUnit                   as U (Counts, Test (TestList),
                                                    runTestTT)
import qualified Test.HUnit.Util              as U (t)
import qualified Text.Parsec                  as P (alphaNum, eof, letter,
                                                    oneOf, runP, (<?>), (<|>))
import qualified Text.Parsec.Expr             as P (Assoc (AssocLeft),
                                                    Operator (Infix, Prefix),
                                                    buildExpressionParser)
import qualified Text.Parsec.Token            as P (GenLanguageDef (LanguageDef),
                                                    caseSensitive, commentEnd,
                                                    commentLine, commentStart,
                                                    identLetter, identStart,
                                                    identifier, makeTokenParser,
                                                    nestedComments, opLetter,
                                                    opStart, parens, reserved,
                                                    reservedNames, reservedOp,
                                                    reservedOpNames, whiteSpace)
import qualified Text.PrettyPrint.ANSI.Leijen as PP (text, (<>))

-- 2.1

data Formula a =
    F
  | T
  | Atom  a
  | Not   (Formula a)
  | And   (Formula a) (Formula a)
  | Or    (Formula a) (Formula a)
  | Impl  (Formula a) (Formula a)
  | Iff   (Formula a) (Formula a)
  | Forall String     (Formula a)
  | Exists String     (Formula a)
  deriving (Eq, Show)

------------------------------------------------------------------------------
-- Parser

langDef = P.LanguageDef
    { P.commentStart    = "{-"
    , P.commentEnd      = "-}"
    , P.commentLine     = "--"
    , P.nestedComments  = True
    , P.identStart      = P.letter
    , P.identLetter     = P.alphaNum
    , P.opStart         = P.oneOf "~^v-<"
    , P.opLetter        = P.oneOf ">"
    , P.reservedNames   = ["v"]
    , P.reservedOpNames = ["~","^","v","->","<>"]
    , P.caseSensitive   = True
    }

lexer        = P.makeTokenParser langDef
identifier   = P.identifier lexer
parens       = P.parens     lexer
reserved     = P.reserved   lexer
reservedOp   = P.reservedOp lexer
whiteSpace   = P.whiteSpace lexer

-- TMP
pimpl = P.runP (reservedOp "-->") (3::Int) "foo"
piff  = P.runP (reservedOp "<->") (3::Int) "foo"

-- parser that return Either
p = P.runP start (3::Int) "foo"

-- parser that expects success
pr x = let (Right r) = p x in r

{- parses a term, followed by whitespace and end-of-file -}
start = do
    e <- formula
    whiteSpace
    P.eof
    return e

formula = P.buildExpressionParser table operatorOrAtom P.<?> "formula"

operatorOrAtom =
          parens formula
    P.<|> atom
    P.<?> "operatorOrAtom"

atom = do
    a <- identifier
    return (Atom a)

table = [ [ prefix "~"   Not ]
        , [ binary "^"   And  P.AssocLeft ]
        , [ binary "v"   Or   P.AssocLeft ]
        , [ binary "->" Impl P.AssocLeft ] -- TODO "-->"
        , [ binary "<>" Iff  P.AssocLeft ] -- TODO "<->"
        ]

--      name fun assoc
binary  name fun       = P.Infix  (reservedOp name >> return fun)
prefix  name fun       = P.Prefix (reservedOp name >> return fun)

tp0 = U.t "tp0"
      (pr "~(~p ^ ~q)")
      (Not (And (Not (Atom "p")) (Not (Atom "q"))))

tp1 = U.t "tp1"
      (pr "p ^ q")
      (And (Atom "p") (Atom "q"))

tp2 = U.t "tp2"
      (pr "p v q ^ z")
      (Or (Atom "p") (And (Atom "q") (Atom "z")))

tp3 = U.t "tp3"
      (pr "p v q -> r")
      (Impl (Or (Atom "p") (Atom "q")) (Atom "r"))

tp4 = U.t "tp4"
      (pr "p <> r")
      (Iff (Atom "p") (Atom "r"))

------------------------------------------------------------------------------
-- pretty printer

data ComingFrom = A | O

showFormula f0 = case f0 of
    (Atom    a) -> PP.text a
    (Not     f) -> PP.text "~" PP.<> showFormula f
    (And f1 f2) -> se f1 A PP.<> PP.text " ^ " PP.<> se f2 A
    (Or  f1 f2) -> se f1 O PP.<> PP.text " v " PP.<> se f2 O
  where
    se f from = case (f, from) of
        (a@(Atom  _),_) -> showFormula a
        (n@(Not   _),_) -> showFormula n
        (a@(And _ _),A) -> showFormula a
        (o@(Or  _ _),O) -> showFormula o
        (f'         ,_) -> PP.text "(" PP.<> showFormula f' PP.<> PP.text ")"

ts1 = U.t "tShowFormula"
    (show (showFormula (pr "(p v q v r) ^ (p v q v  r ^ x  v y)")))
                           "(p v q v r) ^ (p v q v (r ^ x) v y)"

test :: IO U.Counts
test =
    U.runTestTT $ U.TestList $ tp0 ++ tp1 ++ tp2 ++ tp3 ++ tp4 ++
                               ts1

------------------------------------------------------------------------------
-- helper functions

newtype Prop = P { pname :: String }


-- end of file ---