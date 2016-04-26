@doc """`lqr(A, B, Q, R)`

Calculate the optimal gain matrix `K` for the state-feedback law `u = K*x` that
minimizes the cost function:

J = integral(x'Qx + u'Ru, 0, inf).

For the continuous time model `dx = Ax + Bu`.

`lqr(sys, Q, R)`

Solve the LQR problem for state-space system `sys`. Works for both discrete
and continuous time systems.

See also `lqg`

Usage example:
```julia
A = [0 1; 0 0]
B = [0;1]
C = [1 0]
sys = ss(A,B,C,0)
Q = eye(2)
R = eye(1)
L = lqr(sys,Q,R)

u(t,x) = -L*x # Form control law,
t=0:0.1:5
x0 = [1,0]
y, t, x, uout = lsim(sys,u,t,x0)
plot(t,x, lab=["Position", "Velocity"]', xlabel="Time [s]")
```
""" ->
function lqr(A, B, Q, R)
    S = care(A, B, Q, R)
    K = R\B'*S
    return K
end

@doc """`kalman(A, C, R1, R2)` kalman(sys, R1, R2)`

Calculate the optimal Kalman gain

See also `lqg`

""" ->
kalman(A, C, R1,R2) = lqr(A',C',R1,R2)'

function lqr(sys::StateSpace, Q, R)
    if iscontinuous(sys)
        return lqr(sys.A, sys.B, Q, R)
    else
        return dlqr(sys.A, sys.B, Q, R)
    end
end

function kalman(sys::StateSpace, R1,R2)
    if iscontinuous(sys)
        return lqr(sys.A', sys.C', R1,R2)'
    else
        return dlqr(sys.A', sys.C', R1,R2)'
    end
end

"""
`G = lqg(A,B,C,D, Q1, Q2, R1, R2)`

`G = lqg(sys, Q1, Q2, R1, R2)`

calls `lqr` and `kalman` and forms the closed-loop system

returns an LQG object, see `LQG`

See also `lqgi`
"""
function lqg(A,B,C,D, Q1, Q2, R1, R2; qQ=0, qR=0)
    n = size(A,1)
    m = size(B,2)
    p = size(C,1)
    L = lqr(A, B, Q1+qQ*C'C, Q2)
    K = kalman(A, C, R1+qR*B*B', R2)

    # Controller system
    Ac=A-B*L-K*C+K*D*L
    Bc=K
    Cc=L
    Dc=zeros(D')
    sysc = ss(Ac,Bc,Cc,Dc)

    return LQG(P,Q1,Q2,R1,R2, qQ, qR, sysc, L, K, false)

end

function lqg(sys, Q1, Q2, R1, R2)
    lqg(sys.A,sys.B,sys.C,sys.D,Q1,Q2,R1,R2)
end

function lqg(G::LQG)
    f = G.integrator ? lqgi : lqg
    f(G.P.A, G.P.B, G.P.C, G.P.D, G.Q1, G.Q2, G.R1, G.R2, qQ=G.qQ, qR=G.qR)
end

"""
`G = lqgi(A,B,C,D, Q1, Q2, R1, R2)`

`G = lqgi(sys, Q1, Q2, R1, R2)`

Adds a model of a constant disturbance on the inputs to the system described by `A,B,C,D`,
calls `lqr` and `kalman` and forms the closed-loop system. The resulting controller will have intregral action.

returns an LQG object, see `LQG`

See also `lqg`
"""
function lqgi(A,B,C,D, Q1, Q2, R1, R2; qQ=0, qR=0)
    n = size(A,1)
    m = size(B,2)
    p = size(C,1)

    # Augment with disturbance model
    Ae = [A B; zeros(m,n+m)]
    Be = [B;zeros(m,m)]
    Ce = [C zeros(p,m)]
    De = D

    L = lqr(A, B, Q1+qQ*C'C, Q2)
    Le = [L eye(m)]
    K = kalman(Ae, Ce, R1+qR*Be*Be', R2)

    # Controller system
    Ac=Ae-Be*Le-K*Ce+K*De*Le
    Bc=K
    Cc=Le
    Dc=zeros(D')
    sysc = ss(Ac,Bc,Cc,Dc)

    LQG(P,Q1,Q2,R1,R2, qQ, qR, sysc, Le, K, true)
end

function lqgi(sys, Q1, Q2, R1, R2)
    lqgi(sys.A,sys.B,sys.C,sys.D,Q1,Q2,R1,R2)
end

@doc """`dlqr(A, B, Q, R)`, `dlqr(sys, Q, R)`

Calculate the optimal gain matrix `K` for the state-feedback law `u[k] = K*x[k]` that
minimizes the cost function:

J = sum(x'Qx + u'Ru, 0, inf).

For the discrte time model `x[k+1] = Ax[k] + Bu[k]`.

See also `lqg`

Usage example:
```julia
h = 0.1
A = [1 h; 0 1]
B = [0;1]
C = [1 0]
sys = ss(A,B,C,0, h)
Q = eye(2)
R = eye(1)
L = dlqr(A,B,Q,R) # lqr(sys,Q,R) can also be used

u(t,x) = -L*x # Form control law,
t=0:h:5
x0 = [1,0]
y, t, x, uout = lsim(sys,u,t,x0)
plot(t,x, lab=["Position", "Velocity"]', xlabel="Time [s]")
```
""" ->
function dlqr(A, B, Q, R)
    S = dare(A, B, Q, R)
    K = (B'*S*B + R)\(B'S*A)
    return K
end

@doc """`dkalman(A, C, R1, R2)` kalman(sys, R1, R2)`

Calculate the optimal Kalman gain for discrete time systems

""" ->
dkalman(A, C, R1,R2) = dlqr(A',C',R1,R2)'

@doc """`place(A, B, p)`, `place(sys::StateSpace, p)`

Calculate gain matrix `K` such that
the poles of `(A-BK)` in are in `p`""" ->
function place(A, B, p)
    n = length(p)
    n != size(A,1) && error("Must define as many poles as states")
    n != size(B,1) && error("A and B must have same number of rows")
    if size(B,2) == 1
        acker(A,B,p)
    else
        error("place only implemented for SISO systems")
    end
end

function place(sys::StateSpace, p)
    return place(sys.A, sys.B, p)
end

#Implements Ackermann's formula for placing poles of (A-BK) in p
function acker(A,B,P)
    n = length(P)
    #Calculate characteristic polynomial
    poly = reduce(*,Poly([1]),[Poly([1, -p]) for p in P])
    q = zero(Array{promote_type(eltype(A),Float64),2}(n,n))
    for i = n:-1:0
        q += A^(n-i)*poly[i+1]
    end
    S = Array{promote_type(eltype(A),eltype(B),Float64),2}(n,n)
    for i = 0:(n-1)
        S[:,i+1] = A^i*B
    end
    return [zeros(1,n-1) 1]*(S\q)
end


"""
`feedback(L)` Returns L/(1+L)
`feedback(P,C)` Returns PC/(1+PC)
"""
feedback(L::TransferFunction) = L/(1+L)
feedback(P::TransferFunction, C::TransferFunction) = feedback(P*C)

#Efficient implementations
function feedback{T<:SisoRational}(L::TransferFunction{T})
    if size(L) != (1,1)
        error("MIMO TransferFunction inversion isn't implemented yet")
    end
    P = numpoly(L)
    Q = denpoly(L)
    #Extract polynomials and create P/(P+Q)
    tf(P[1][:],(P+Q)[1][:], Ts=L.Ts)
end

function ControlSystems.feedback{T<:ControlSystems.SisoZpk}(L::TransferFunction{T})
    if size(L) != (1,1)
        error("MIMO TransferFunction inversion isn't implemented yet")
    end
    numer = num(L.matrix[1])
    k = L.matrix[1].k
    denpol = k*prod(numpoly(L)[1])+prod(denpoly(L)[1])
    kden = denpol[1]
    #Extract polynomials and create P/(P+Q)
    zpk(numer,ControlSystems.roots(denpol), k/kden, Ts=L.Ts)
end

"""
`feedback(sys)`

`feedback(sys1,sys2)`

Forms the negative feedback interconnection
```julia
>-+ sys1 +-->
  |      |
 (-)sys2 +
```
If no second system is given, negative identity feedback is assumed
"""
function feedback(sys::StateSpace)
    sys.ny != sys.nu && error("Use feedback(sys1::StateSpace,sys2::StateSpace) if sys.ny != sys.nu")
    feedback(sys,ss(eye(sys.ny)))
end

function feedback(sys1::StateSpace,sys2::StateSpace)
    sum(abs.(sys1.D)) != 0 && sum(abs.(sys2.D)) != 0 && error("There can not be a direct term (D) in both sys1 and sys2")
    A = [sys1.A+sys1.B*(-sys2.D)*sys1.C sys1.B*(-sys2.C); sys2.B*sys1.C  sys2.A+sys2.B*sys1.D*(-sys2.C)]
    B = [sys1.B; sys2.B*sys1.D]
    C = [sys1.C  sys1.D*(-sys2.C)]
    ss(A,B,C,sys1.D)
end


"""
`feedback2dof(P,R,S,T)` Return `BT/(AR+ST)` where B and A are the numerator and denomenator polynomials of `P` respectively
`feedback2dof(B,A,R,S,T)` Return `BT/(AR+ST)`
"""
function feedback2dof(P::TransferFunction,R,S,T)
    !issiso(P) && error("Feedback not implemented for MIMO systems")
    tf(conv(poly2vec(numpoly(P)[1]),T),zpconv(poly2vec(denpoly(P)[1]),R,poly2vec(numpoly(P)[1]),S))
end

feedback2dof(B,A,R,S,T) = tf(conv(B,T),zpconv(A,R,B,S))
