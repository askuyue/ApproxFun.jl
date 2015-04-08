#############
# Schur PDEOperator
# represent an operator that's been discretized in the Y direction
#############


abstract AbstractPDEOperatorSchur

immutable PDEOperatorSchur{OS<:AbstractOperatorSchur,LT<:Number,MT<:Number,ST<:Number,FT<:Functional} <: AbstractPDEOperatorSchur
    Bx::Vector{FT}
    Lx::Operator{LT}
    Mx::Operator{MT}
    S::OS

    indsBx::Vector{Int}
    indsBy::Vector{Int}

    Rdiags::Vector{SavedBandedOperator{ST}}
end

#TODO: Functional type?
Base.eltype{OS,LT,MT,ST,FT}(PO::PDEOperatorSchur{OS,LT,MT,ST,FT})=promote_type(eltype(PO.S),LT,MT,ST)


function PDEOperatorSchur{LT<:Number,MT<:Number,BT<:Number,ST<:Number}(Bx,Lx::Operator{LT},Mx::Operator{MT},S::AbstractOperatorSchur{BT,ST},indsBx,indsBy)
    Xops=promotespaces([Lx,Mx])
    Lx=SavedBandedOperator(Xops[1]);Mx=SavedBandedOperator(Xops[2])

    ny=size(S,1)
    nbcs=numbcs(S)
    RT=promote_type(LT,MT,BT,ST)
    Rdiags=Array(SavedBandedOperator{RT},ny)

    resizedata!(Lx,ny);resizedata!(Mx,ny)


    for k=1:ny-nbcs
        ##TODO: Do block case
        Rdiags[k]=SavedBandedOperator(PlusOperator(BandedOperator{RT}[getdiagonal(S,k,1)*Lx,getdiagonal(S,k,2)*Mx]))
        resizedata!(Rdiags[k],ny)
    end

    if isempty(Bx)
        funcs=Array(SavedFunctional{Float64},0)
    else
        funcs=Array(SavedFunctional{mapreduce(eltype,promote_type,Bx)},length(Bx))
        for k=1:length(Bx)
            funcs[k]=SavedFunctional(Bx[k])
            resizedata!(funcs[k],ny)
        end
    end


    PDEOperatorSchur(funcs,Lx,Mx,S,indsBx,indsBy,Rdiags)
end




PDEOperatorSchur(Bx::Vector,Lx::Operator,Mx::Operator,S::AbstractOperatorSchur)=PDEOperatorSchur(Bx,Lx,Mx,S,[1:length(Bx)],length(Bx)+[1:numbcs(S)])
PDEOperatorSchur(Bx::Vector,Lx::Operator,Mx::UniformScaling,S::AbstractOperatorSchur)=PDEOperatorSchur(Bx,Lx,ConstantOperator(Mx.λ),S)
PDEOperatorSchur(Bx::Vector,Lx::UniformScaling,Mx::Operator,S::AbstractOperatorSchur)=PDEOperatorSchur(Bx,ConstantOperator(Lx.λ),Mx,S)


function PDEOperatorSchur(Bx,By,A::PlusOperator,ny::Integer,indsBx,indsBy)
    @assert all(isproductop,A.ops)
    @assert length(A.ops)==2

    PDEOperatorSchur(Bx,dekron(A.ops[1],1),dekron(A.ops[2],1),schurfact(By,[dekron(A.ops[1],2),dekron(A.ops[2],2)],ny),indsBx,indsBy)
end




bcinds(S::PDEOperatorSchur,k)=k==1?S.indsBx:S.indsBy
numbcs(S::AbstractPDEOperatorSchur,k)=length(bcinds(S,k))
Base.length(S::PDEOperatorSchur)=size(S.S,1)


function PDEOperatorSchur(A::Vector,ny::Integer)
    indsBx,Bx=findfunctionals(A,1)
    indsBy,By=findfunctionals(A,2)

    LL=A[end]


    PDEOperatorSchur(Bx,By,LL,ny,indsBx,indsBy)
end



for op in (:domainspace,:rangespace)
    @eval begin
        $op(P::PDEOperatorSchur,k::Integer)=k==1?$op(P.Lx):$op(P.S)
        $op(L::PDEOperatorSchur)=$op(L,1)⊗$op(L,2)
    end
end


domain(P::PDEOperatorSchur,k::Integer)=k==1?domain(P.Lx):domain(P.S)
domain(P::PDEOperatorSchur)=domain(domainspace(P))



#############
# PDEStrideOperatorSchur
#############


immutable PDEStrideOperatorSchur  <: AbstractPDEOperatorSchur
    odd
    even
end


function PDEStrideOperatorSchur(Bx,Lx::Operator,Mx::Operator,S::StrideOperatorSchur,indsBx,indsBy)
    @assert indsBy==[3,4]
    Podd=PDEOperatorSchur(Bx,Lx,Mx,S.odd,indsBx,[indsBy[1]])
    Peven=PDEOperatorSchur(Bx,Lx,Mx,S.even,indsBx,[indsBy[1]])

    PDEStrideOperatorSchur(Podd,Peven)
end

###############
# Product
# Represents an operator on e.g. a Disk
#############

immutable PDEProductOperatorSchur{ST<:Number,
                                  FT<:Functional,
                                  DS<:AbstractProductSpace,
                                  RS<:AbstractProductSpace,
                                  S<:FunctionSpace,
                                  V<:FunctionSpace} <: AbstractPDEOperatorSchur
    Bx::Vector{Vector{FT}}
    Rdiags::Vector{SavedBandedOperator{ST}}
    domainspace::DS
    rangespace::RS
    indsBx::Vector{Int}
end

PDEProductOperatorSchur{ST,FT,S,V}(Bx::Vector{Vector{FT}},
                                   Rdiags::Vector{SavedBandedOperator{ST}},
                                   ds::AbstractProductSpace{S,V},rs,indsBx)=PDEProductOperatorSchur{ST,FT,typeof(ds),typeof(rs),S,V}(Bx,Rdiags,ds,rs,indsBx)

Base.eltype{ST}(::PDEProductOperatorSchur{ST})=ST

Base.length(S::PDEProductOperatorSchur)=length(S.Rdiags)

domain(P::PDEProductOperatorSchur)=domain(domainspace(P))

function PDEProductOperatorSchur{OT<:Operator}(A::Vector{OT},sp::AbstractProductSpace,nt::Integer)
    indsBx,Bx=findfunctionals(A,1)
    @assert isempty(findfunctionals(A,2)[1])
    L=A[end]
    S=schurfact(Functional{eltype(eltype(L))}[],dekron(L,2,:),nt)
    @assert(isa(S,DiagonalOperatorSchur))

    #TODO: Space Type
    BxV=Array(Vector{SavedFunctional{Float64}},nt)
    Rdiags=Array(SavedBandedOperator{Complex{Float64}},nt)
    rops=dekron(L,1,:)
    for k=1:nt
        op=getdiagonal(S,k,1)*rops[1]
        for j=2:length(L)
            Skj=getdiagonal(S,k,j)
            if Skj!=0   # don't add unnecessary ops
                op+=Skj*rops[j]
            end
        end

        csp=columnspace(sp,k)
        Rdiags[k]=SavedBandedOperator(promotedomainspace(op,csp))
        BxV[k]=SavedFunctional{Float64}[SavedFunctional(promotedomainspace(Bxx,csp)) for Bxx in Bx]
        resizedata!(Rdiags[k],2nt+100)
        for Bxx in BxV[k]
            resizedata!(Bxx,2nt+100)
        end
    end
    PDEProductOperatorSchur(BxV,Rdiags,sp,rangespace(L),indsBx)
end

PDEProductOperatorSchur{OT<:Operator}(A::Vector{OT},sp::BivariateDomain,nt::Integer)=PDEProductOperatorSchur(A,Space(sp),nt)


##TODO: Larger Bx
bcinds(S::PDEProductOperatorSchur,k)=k==1?S.indsBx:[]
domainspace(S::PDEProductOperatorSchur)=S.domainspace
domainspace(S::PDEProductOperatorSchur,k)=S.domainspace[k]
rangespace(S::PDEProductOperatorSchur)=S.rangespace

# for op in (:domainspace,:rangespace)
#     @eval begin
#         $op(P::PDEProductOperatorSchur,k::Integer)=k==1?$op(P.Lx):$op(P.S)
#        $op(L::PDEProductOperatorSchur)=$op(L,1)⊗$op(L,2)
#     end
# end





##
# ProductRangeSpace avoids computing the column spaces
##



# type ProductRangeSpace{PDEP<:PDEProductOperatorSchur,SS,VV} <: AbstractProductSpace{SS,VV}
#     S::PDEP
# end

# ProductRangeSpace{ST,FT,DS,S,V}(s::PDEProductOperatorSchur{ST,FT,DS,S,V})=ProductRangeSpace{typeof(s),S,V}(s)



# function space(S::ProductRangeSpace,k)
#     @assert k==2
#     S.S.domainspace[2]
# end

# columnspace(S::ProductRangeSpace,k)=rangespace(S.S.Rdiags[k])

# function coefficients{S,V,SS,T}(f::ProductFun{S,V,SS,T},sp::ProductRangeSpace)
#     @assert space(f,2)==space(sp,2)

#     n=min(size(f,2),length(sp.S))
#     F=[coefficients(f.coefficients[k],rangespace(sp.S.Rdiags[k])) for k=1:n]
#     m=mapreduce(length,max,F)
#     ret=zeros(T,m,n)
#     for k=1:n
#         ret[1:length(F[k]),k]=F[k]
#     end
#     ret
# end



## Constructuor


Base.schurfact{LT<:Number,MT<:Number,BT<:Number,ST<:Number}(Bx,Lx::Operator{LT},Mx::Operator{MT},S::AbstractOperatorSchur{BT,ST},indsBx,indsBy)=PDEOperatorSchur(Bx,Lx,Mx,S,indsBx,indsBy)
Base.schurfact{LT<:Number,MT<:Number,ST<:Number}(Bx,Lx::Operator{LT},Mx::Operator{MT},S::StrideOperatorSchur{ST},indsBx,indsBy)=PDEStrideOperatorSchur(Bx,Lx,Mx,S,indsBx,indsBy)

function Base.schurfact{T}(Bx,By,A::PlusOperator{BandedMatrix{T}},ny::Integer,indsBx,indsBy)
    @assert all(g->isa(g,KroneckerOperator),A.ops)
    @assert length(A.ops)==2

    schurfact(Bx,A.ops[1].ops[1],A.ops[2].ops[1],schurfact(By,[A.ops[1].ops[2],A.ops[2].ops[2]],ny),indsBx,indsBy)
end



function Base.schurfact{BT<:BandedOperator}(A::Vector{BT},S::ProductDomain,ny::Integer)
    indsBx,Bx=findfunctionals(A,1)
    indsBy,By=findfunctionals(A,2)

    LL=A[end]


    schurfact(Bx,By,LL,ny,indsBx,indsBy)
end





Base.schurfact{BT<:Operator}(A::Vector{BT},S::BivariateDomain,n::Integer)=PDEProductOperatorSchur(A,S,n)


Base.schurfact{BT<:Operator}(A::Vector{BT},n::Integer)=schurfact(A,domain(A[end]),n)
Base.schurfact{T}(A::BivariateOperator{T},n::Integer)=schurfact([A],n)

function *(A::PDEProductOperatorSchur,F::ProductFun)
    ret=copy(F.coefficients)
    for k=1:length(ret)
        ret[k]=A.Rdiags[k]*ret[k]
    end
    ProductFun(ret,space(F))
end




## discretize

#TODO: don't hard code Disk
discretize{OT<:Operator}(A::Vector{OT},S...)=(isa(A[end],PlusOperator)&&length(A[end].ops)==2)||domain(A[end])==Disk()?schurfact(A,S...):kron(A,S...)
discretize{T}(A::BivariateOperator{T},n::Integer)=discretize([A],n)


