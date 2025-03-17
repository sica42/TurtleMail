L = {}
setmetatable( L, { __index = function( _, key) return key end } );

L[ "collected" ] = nil
L[ "1st mail" ] = nil
L[ "each mail" ] = nil
L[ "Money received" ] = nil
L[ "All mails" ] = nil
L[ "This mail was returned to you." ] = nil
L[ "This mail was sent by an auctionhouse." ] = nil