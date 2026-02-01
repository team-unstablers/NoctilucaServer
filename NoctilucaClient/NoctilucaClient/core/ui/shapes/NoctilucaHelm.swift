//
//  NoctilucaHelm.swift
//  NoctilucaClient
//
//  Created by Gyuhwan Park on 12/19/25.
//

import SwiftUI

struct NoctilucaHelm: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let width = rect.size.width
        let height = rect.size.height
        path.move(to: CGPoint(x: 0.81641*width, y: height))
        path.addLine(to: CGPoint(x: 0.76953*width, y: height))
        path.addCurve(to: CGPoint(x: 0.74219*width, y: 0.89941*height), control1: CGPoint(x: 0.76953*width, y: 0.98047*height), control2: CGPoint(x: 0.74512*width, y: 0.94141*height))
        path.addLine(to: CGPoint(x: 0.73926*width, y: 0.85059*height))
        path.addCurve(to: CGPoint(x: 0.72949*width, y: 0.84863*height), control1: CGPoint(x: 0.73828*width, y: 0.84473*height), control2: CGPoint(x: 0.73535*width, y: 0.84766*height))
        path.addCurve(to: CGPoint(x: 0.57031*width, y: 0.90918*height), control1: CGPoint(x: 0.65137*width, y: 0.85938*height), control2: CGPoint(x: 0.59766*width, y: 0.89063*height))
        path.addCurve(to: CGPoint(x: 0.57813*width, y: 0.9248*height), control1: CGPoint(x: 0.56445*width, y: 0.91211*height), control2: CGPoint(x: 0.56836*width, y: 0.91406*height))
        path.addCurve(to: CGPoint(x: 0.63477*width, y: 0.99414*height), control1: CGPoint(x: 0.58887*width, y: 0.9375*height), control2: CGPoint(x: 0.61914*width, y: 0.96875*height))
        path.addLine(to: CGPoint(x: 0.63672*width, y: 0.99805*height))
        path.addLine(to: CGPoint(x: 0.63672*width, y: height))
        path.addLine(to: CGPoint(x: 0.51172*width, y: height))
        path.addLine(to: CGPoint(x: 0.50977*width, y: 0.99707*height))
        path.addLine(to: CGPoint(x: 0.50586*width, y: 0.99414*height))
        path.addLine(to: CGPoint(x: 0.49316*width, y: 0.98535*height))
        path.addLine(to: CGPoint(x: 0.48828*width, y: 0.9834*height))
        path.addLine(to: CGPoint(x: 0.47656*width, y: 0.99805*height))
        path.addLine(to: CGPoint(x: 0.47656*width, y: height))
        path.addLine(to: CGPoint(x: 0.27637*width, y: height))
        path.addLine(to: CGPoint(x: 0.27734*width, y: 0.99512*height))
        path.addCurve(to: CGPoint(x: 0.32031*width, y: 0.91797*height), control1: CGPoint(x: 0.2793*width, y: 0.99219*height), control2: CGPoint(x: 0.29199*width, y: 0.96094*height))
        path.addCurve(to: CGPoint(x: 0.34863*width, y: 0.875*height), control1: CGPoint(x: 0.33398*width, y: 0.89551*height), control2: CGPoint(x: 0.34961*width, y: 0.87793*height))
        path.addCurve(to: CGPoint(x: 0.31934*width, y: 0.83105*height), control1: CGPoint(x: 0.34766*width, y: 0.87012*height), control2: CGPoint(x: 0.31738*width, y: 0.84863*height))
        path.addCurve(to: CGPoint(x: 0.31641*width, y: 0.82031*height), control1: CGPoint(x: 0.32031*width, y: 0.8252*height), control2: CGPoint(x: 0.32031*width, y: 0.82422*height))
        path.addCurve(to: CGPoint(x: 0.29492*width, y: 0.79688*height), control1: CGPoint(x: 0.30469*width, y: 0.80664*height), control2: CGPoint(x: 0.30762*width, y: 0.80371*height))
        path.addCurve(to: CGPoint(x: 0.11328*width, y: 0.64844*height), control1: CGPoint(x: 0.26465*width, y: 0.7793*height), control2: CGPoint(x: 0.12793*width, y: 0.67285*height))
        path.addCurve(to: CGPoint(x: 0.15039*width, y: 0.55566*height), control1: CGPoint(x: 0.08691*width, y: 0.60352*height), control2: CGPoint(x: 0.14551*width, y: 0.5625*height))
        path.addCurve(to: CGPoint(x: 0.17871*width, y: 0.53027*height), control1: CGPoint(x: 0.15332*width, y: 0.55078*height), control2: CGPoint(x: 0.1543*width, y: 0.54688*height))
        path.addCurve(to: CGPoint(x: 0.22656*width, y: 0.53027*height), control1: CGPoint(x: 0.18359*width, y: 0.52637*height), control2: CGPoint(x: 0.20703*width, y: 0.51563*height))
        path.addCurve(to: CGPoint(x: 0.31543*width, y: 0.63184*height), control1: CGPoint(x: 0.24707*width, y: 0.54688*height), control2: CGPoint(x: 0.26563*width, y: 0.57324*height))
        path.addCurve(to: CGPoint(x: 0.37695*width, y: 0.71094*height), control1: CGPoint(x: 0.32031*width, y: 0.6377*height), control2: CGPoint(x: 0.35938*width, y: 0.68359*height))
        path.addCurve(to: CGPoint(x: 0.38867*width, y: 0.72656*height), control1: CGPoint(x: 0.38281*width, y: 0.71875*height), control2: CGPoint(x: 0.37988*width, y: 0.7207*height))
        path.addCurve(to: CGPoint(x: 0.41211*width, y: 0.74023*height), control1: CGPoint(x: 0.40332*width, y: 0.73535*height), control2: CGPoint(x: 0.40137*width, y: 0.74121*height))
        path.addCurve(to: CGPoint(x: 0.45898*width, y: 0.77246*height), control1: CGPoint(x: 0.43066*width, y: 0.74023*height), control2: CGPoint(x: 0.45313*width, y: 0.77441*height))
        path.addCurve(to: CGPoint(x: 0.55566*width, y: 0.7168*height), control1: CGPoint(x: 0.46289*width, y: 0.77051*height), control2: CGPoint(x: 0.49316*width, y: 0.74512*height))
        path.addCurve(to: CGPoint(x: 0.6582*width, y: 0.68164*height), control1: CGPoint(x: 0.59473*width, y: 0.69922*height), control2: CGPoint(x: 0.61914*width, y: 0.69141*height))
        path.addCurve(to: CGPoint(x: 0.71582*width, y: 0.67188*height), control1: CGPoint(x: 0.68652*width, y: 0.67578*height), control2: CGPoint(x: 0.68652*width, y: 0.67578*height))
        path.addCurve(to: CGPoint(x: 0.73145*width, y: 0.61719*height), control1: CGPoint(x: 0.72461*width, y: 0.66992*height), control2: CGPoint(x: 0.71094*width, y: 0.63184*height))
        path.addCurve(to: CGPoint(x: 0.73633*width, y: 0.58887*height), control1: CGPoint(x: 0.7373*width, y: 0.61328*height), control2: CGPoint(x: 0.7334*width, y: 0.60254*height))
        path.addCurve(to: CGPoint(x: 0.71875*width, y: 0.4668*height), control1: CGPoint(x: 0.73828*width, y: 0.5791*height), control2: CGPoint(x: 0.73047*width, y: 0.58008*height))
        path.addCurve(to: CGPoint(x: 0.72656*width, y: 0.32031*height), control1: CGPoint(x: 0.70703*width, y: 0.35645*height), control2: CGPoint(x: 0.7041*width, y: 0.34082*height))
        path.addCurve(to: CGPoint(x: 0.79102*width, y: 0.30469*height), control1: CGPoint(x: 0.74609*width, y: 0.30273*height), control2: CGPoint(x: 0.78516*width, y: 0.30371*height))
        path.addCurve(to: CGPoint(x: 0.82715*width, y: 0.30469*height), control1: CGPoint(x: 0.80859*width, y: 0.30469*height), control2: CGPoint(x: 0.80859*width, y: 0.30273*height))
        path.addCurve(to: CGPoint(x: 0.87012*width, y: 0.32617*height), control1: CGPoint(x: 0.83203*width, y: 0.30566*height), control2: CGPoint(x: 0.85742*width, y: 0.30664*height))
        path.addCurve(to: CGPoint(x: 0.86621*width, y: 0.47266*height), control1: CGPoint(x: 0.88184*width, y: 0.3457*height), control2: CGPoint(x: 0.87305*width, y: 0.39551*height))
        path.addCurve(to: CGPoint(x: 0.85059*width, y: 0.58594*height), control1: CGPoint(x: 0.85938*width, y: 0.56152*height), control2: CGPoint(x: 0.85449*width, y: 0.57715*height))
        path.addCurve(to: CGPoint(x: 0.85645*width, y: 0.61914*height), control1: CGPoint(x: 0.85059*width, y: 0.58691*height), control2: CGPoint(x: 0.85352*width, y: 0.61621*height))
        path.addCurve(to: CGPoint(x: 0.87012*width, y: 0.6748*height), control1: CGPoint(x: 0.87402*width, y: 0.63672*height), control2: CGPoint(x: 0.86035*width, y: 0.67285*height))
        path.addCurve(to: CGPoint(x: 0.99414*width, y: 0.70996*height), control1: CGPoint(x: 0.87012*width, y: 0.6748*height), control2: CGPoint(x: 0.92969*width, y: 0.68359*height))
        path.addLine(to: CGPoint(x: width, y: 0.71191*height))
        path.addLine(to: CGPoint(x: width, y: 0.91504*height))
        path.addLine(to: CGPoint(x: 0.99512*width, y: 0.91309*height))
        path.addCurve(to: CGPoint(x: 0.90039*width, y: 0.86523*height), control1: CGPoint(x: 0.95313*width, y: 0.88184*height), control2: CGPoint(x: 0.90234*width, y: 0.86621*height))
        path.addCurve(to: CGPoint(x: 0.84863*width, y: 0.85449*height), control1: CGPoint(x: 0.85156*width, y: 0.85059*height), control2: CGPoint(x: 0.84863*width, y: 0.85059*height))
        path.addCurve(to: CGPoint(x: 0.81738*width, y: 0.99805*height), control1: CGPoint(x: 0.8457*width, y: 0.92871*height), control2: CGPoint(x: 0.84473*width, y: 0.92969*height))
        path.addLine(to: CGPoint(x: 0.81641*width, y: height))
        path.closeSubpath()
        path.move(to: CGPoint(x: 0.9668*width, y: height))
        path.addLine(to: CGPoint(x: 0.9668*width, y: 0.99805*height))
        path.addLine(to: CGPoint(x: width, y: 0.94824*height))
        path.addLine(to: CGPoint(x: width, y: height))
        path.addLine(to: CGPoint(x: 0.9668*width, y: height))
        path.closeSubpath()
        return path.normalized()
    }
}

#Preview {
    if #available(macOS 26.0, iOS 26.0, *) {
        VStack {
            VStack {
            }
            .frame(width: 256, height: 256)
            .glassEffect(.clear.tint(.blue).interactive(), in: NoctilucaHelm())
            .scaleEffect(2)
        }.frame(width: 128 * 4, height: 128 * 4)
    } else {
        EmptyView()
    }
}
