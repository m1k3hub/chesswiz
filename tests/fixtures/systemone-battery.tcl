# ======================================================================
# A labelled calibration battery for the System One gates.
#
# Each feature maps to a list of {state gold} cases. The gold label is the
# correct answer for the *production* question (::ai::<feature>::Question),
# so ::ai::calibrate can measure a backend and pick a threshold. Labels are
# deliberate and, for event_type, derivable from the TimeControl tag.
#
#   source this file, then ::scidb::calibrate::Battery
# ======================================================================

namespace eval ::scidb::calibrate {}

proc ::scidb::calibrate::Battery {} {
return [dict create \
comment_kind {
	{"Develops the bishop to an active diagonal and prepares castling." opening}
	{"This is the main line of the Najdorf." opening}
	{"A gambit trying to seize the initiative in the centre." opening}
	{"White fianchettoes the bishop to control the long diagonal." opening}
	{"The knight forks the king and the rook." tactics}
	{"A skewer wins the queen." tactics}
	{"This pin on the knight is decisive." tactics}
	{"White sacrifices the exchange to open the king." tactics}
	{"A discovered attack on the queen wins material." tactics}
	{"The rook ending is drawn with correct technique." endgame}
	{"Zugzwang: every move loses a pawn." endgame}
	{"The passed pawn decides the game." endgame}
	{"Opposite-coloured bishops favour the attacker here." endgame}
	{"Simplify into a won king and pawn ending." endgame}
	{"White should target the weak dark squares around the king." plan}
	{"A plan of pressure against the backward pawn." plan}
	{"The idea is to manoeuvre the knight to e5." plan}
	{"Seize the initiative with a timely pawn break." plan}
	{"White is clearly better." evaluation}
	{"The position is roughly equal." evaluation}
	{"Black has full compensation for the pawn." evaluation}
	{"Unclear; both sides have chances." evaluation}
	{"White stands slightly worse after the exchange." evaluation}
	{"A blunder; the knight is simply lost." warning}
	{"This is the only move." warning}
	{"Careful, the queen is hanging." warning}
	{"A serious mistake that throws away the advantage." warning}
	{"The time control here is 90 minutes plus 30 seconds." other}
	{"Played in the 1972 World Championship." other}
	{"Black took twelve minutes on this move." other}
} \
language {
	{"White is slightly better after the exchange." en}
	{"The knight forks the king and the rook." en}
	{"Weiß steht nach dem Abtausch etwas besser." de}
	{"Der Springer gabelt König und Turm." de}
	{"Les blancs sont légèrement mieux après l'échange." fr}
	{"Le cavalier fait une fourchette royale." fr}
	{"Las blancas están ligeramente mejor tras el cambio." es}
	{"El caballo hace una horquilla al rey y la torre." es}
	{"Il bianco sta leggermente meglio dopo lo scambio." it}
	{"Il cavallo attacca re e torre con una forchetta." it}
	{"As brancas estão ligeiramente melhor após a troca." pt}
	{"O cavalo faz um garfo no rei e na torre." pt}
	{"Wit staat iets beter na de ruil van stukken." nl}
	{"Het paard vorkt koning en toren." nl}
	{"Białe stoją nieco lepiej po wymianie." pl}
	{"Skoczek atakuje króla i wieżę." pl}
	{"Bílý stojí po výměně o něco lépe." cs}
	{"Jezdec vidličuje krále a věž." cs}
	{"Белые стоят немного лучше после размена." ru}
	{"Конь нападает на короля и ладью." ru}
	{"Білі стоять трохи краще після розміну." uk}
	{"Кінь нападає на короля і туру." uk}
	{"Beyaz değişimden sonra biraz daha iyi durumda." tr}
	{"At şahı ve kaleyi çatalıyor." tr}
	{"Τα λευκά είναι ελαφρώς καλύτερα μετά την ανταλλαγή." el}
	{"Ο ίππος κάνει διπλό χτύπημα." el}
	{"الأبيض أفضل قليلاً بعد التبادل." ar}
	{"الحصان يهاجم الملك والرخ." ar}
	{"הלבן עומד טוב יותר לאחר ההחלפה." he}
	{"הפרש תוקף את המלך והצריח." he}
	{"交换后白方稍好。" zh}
	{"马叉住王和车。" zh}
	{"交換後、白がやや良い。" ja}
	{"ナイトがキングとルークをフォークする。" ja}
	{"교환 후 백이 약간 좋다." ko}
	{"나이트가 킹과 룩을 포크한다." ko}
	{"Nf3 Nc6 Bb5 a6 Ba4 Nf6" xx}
	{"1-0" xx}
}
]
}
