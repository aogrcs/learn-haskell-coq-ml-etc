-- generated by HCPN NetEdit v0.0
module Unnamed where
import SimpleHCPN
import GuiHCPN
import List (intersperse)

-- declarations

-- markings
data Mark = Mark {
    final_bc :: [String]
  , final_ab_c :: [String]
  , sab_ :: [String]
  , sb :: [String]
  , start :: [String]
  } deriving Show
-- transition actions
t5 :: Mark -> [Mark]
t5 m = 
  do
    let sb_marking = sb m
    let final_bc_marking = final_bc m
    ('c':input, sb_marking) <- select $ sb_marking
    if True
     then return m{ 
              sb = sb_marking
            , final_bc = (input) : final_bc_marking
            }
     else fail "guard failed"
t3 :: Mark -> [Mark]
t3 m = 
  do
    let sab__marking = sab_ m
    let final_ab_c_marking = final_ab_c m
    ('c':input, sab__marking) <- select $ sab__marking
    if True
     then return m{ 
              sab_ = sab__marking
            , final_ab_c = (input) : final_ab_c_marking
            }
     else fail "guard failed"
t2 :: Mark -> [Mark]
t2 m = 
  do
    let sab__marking = sab_ m
    ('b':input, sab__marking) <- select $ sab__marking
    if True
     then return m{ 
              sab_ = (input) : sab__marking
            }
     else fail "guard failed"
t4 :: Mark -> [Mark]
t4 m = 
  do
    let start_marking = start m
    let sb_marking = sb m
    ('b':input, start_marking) <- select $ start_marking
    if True
     then return m{ 
              start = start_marking
            , sb = (input) : sb_marking
            }
     else fail "guard failed"
t1 :: Mark -> [Mark]
t1 m = 
  do
    let start_marking = start m
    let sab__marking = sab_ m
    ('a':input, start_marking) <- select $ start_marking
    if True
     then return m{ 
              start = start_marking
            , sab_ = (input) : sab__marking
            }
     else fail "guard failed"
-- transitions
net = Net{trans=[ Trans{name="t5",info=Nothing,action=t5}
                , Trans{name="t3",info=Nothing,action=t3}
                , Trans{name="t2",info=Nothing,action=t2}
                , Trans{name="t4",info=Nothing,action=t4}
                , Trans{name="t1",info=Nothing,action=t1}
                ]} 
-- initial marking
mark = Mark{ final_bc = []
           , final_ab_c = []
           , sab_ = []
           , sb = []
           , start = ["ac","abbbbbbbbbc","bc","bac","aa"]
           } 
-- end of net code

main = simMain "fa_regular.hcpn" showMarking net mark

showMarking pmap = let (Just nV_final_bc) = lookup "final_bc" pmap
                       (Just nV_final_ab_c) = lookup "final_ab_c" pmap
                       (Just nV_sab_) = lookup "sab_" pmap
                       (Just nV_sb) = lookup "sb" pmap
                       (Just nV_start) = lookup "start" pmap
                   in \setPlaceMark m-> do
                         setPlaceMark nV_final_bc (concat $ intersperse "," $ map show $ final_bc m)
                         setPlaceMark nV_final_ab_c (concat $ intersperse "," $ map show $ final_ab_c m)
                         setPlaceMark nV_sab_ (concat $ intersperse "," $ map show $ sab_ m)
                         setPlaceMark nV_sb (concat $ intersperse "," $ map show $ sb m)
                         setPlaceMark nV_start (concat $ intersperse "," $ map show $ start m)
